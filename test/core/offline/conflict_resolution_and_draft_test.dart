import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:labflow/core/offline/admin_entity_draft_store.dart';
import 'package:labflow/core/offline/conflict_resolution.dart';
import 'package:labflow/features/asset/data/asset_service.dart';
import 'package:labflow/features/laboratory/data/laboratory_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../helpers/fake_firestore.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime currentClock;
  late FakeMemoryFirestore firestore;
  late SharedPreferencesAdminEntityDraftStore draftStore;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SharedPreferencesAdminEntityDraftStore.resetRecoveryStateForTesting();
    currentClock = DateTime.utc(2026, 11, 1, 9, 0, 0);
    firestore = FakeMemoryFirestore(clock: () => currentClock);
    draftStore = SharedPreferencesAdminEntityDraftStore();
  });

  group('Task B — Offline Entity Draft Store (Isolation, Persistence & Security)', () {
    test('Persists draft across store instances and isolates strictly by ownerUid', () async {
      final now = DateTime.utc(2026, 11, 1, 9);
      final draftA = OfflineEntityDraft(
        draftId: OfflineEntityDraft.createDraftIdFor(
          entityType: DraftEntityType.laboratory,
          entityId: 'lab-1',
        ),
        ownerUid: 'user-a',
        entityType: DraftEntityType.laboratory,
        entityId: 'lab-1',
        data: const {
          'name': 'Laboratorium IoT',
          'code': 'LAB-IOT-01',
          'location': 'Gedung A',
          'description': 'Draft lokal A',
          'status': 'active',
        },
        baselineData: const {
          'name': 'Laboratorium Awal',
          'code': 'LAB-IOT-01',
          'location': 'Gedung A',
          'description': 'Awal',
          'status': 'active',
        },
        baselineUpdatedAt: now.subtract(const Duration(hours: 1)),
        createdAt: now,
        updatedAt: now,
        syncStatus: DraftSyncStatus.pending,
      );

      await draftStore.saveDraft('user-a', draftA);

      // Simulate app restart with a fresh store instance backed by the same platform storage:
      final restartedStore = SharedPreferencesAdminEntityDraftStore();

      final loadedForA = await restartedStore.readDraftForEntity(
        uid: 'user-a',
        entityType: DraftEntityType.laboratory,
        entityId: 'lab-1',
      );
      expect(loadedForA, isNotNull);
      expect(loadedForA!.data['name'], 'Laboratorium IoT');
      expect(loadedForA.baselineData!['name'], 'Laboratorium Awal');
      expect(loadedForA.syncStatus, DraftSyncStatus.pending);

      // User B must not see User A's drafts:
      final loadedForB = await restartedStore.readDraftForEntity(
        uid: 'user-b',
        entityType: DraftEntityType.laboratory,
        entityId: 'lab-1',
      );
      expect(loadedForB, isNull);
      expect(await restartedStore.listDrafts('user-b'), isEmpty);

      // Attempting to write User A's draft under User B's namespace is rejected:
      await expectLater(
        () => restartedStore.saveDraft('user-b', draftA),
        throwsA(isA<StateError>()),
      );
    });

    test('Strips sensitive keys (password, token, secret) before persisting', () async {
      final now = DateTime.utc(2026, 11, 1, 9);
      final draft = OfflineEntityDraft(
        draftId: OfflineEntityDraft.createDraftIdFor(
          entityType: DraftEntityType.asset,
        ),
        ownerUid: 'admin-1',
        entityType: DraftEntityType.asset,
        data: const {
          'name': 'Oscilloscope',
          'code': 'ELK-OSC-01',
          'password': 'secret-password',
          'authToken': 'bearer-xyz',
          'clientSecret': 'top-secret',
        },
        createdAt: now,
        updatedAt: now,
      );

      await draftStore.saveDraft('admin-1', draft);
      final loaded = await draftStore.readDraft('admin-1', draft.draftId);
      expect(loaded, isNotNull);
      expect(loaded!.data.containsKey('password'), isFalse);
      expect(loaded.data.containsKey('authToken'), isFalse);
      expect(loaded.data.containsKey('clientSecret'), isFalse);
      expect(loaded.data['name'], 'Oscilloscope');
    });

    test('Recovers draft stuck in syncing state after app force-stop/restart', () async {
      final now = DateTime.utc(2026, 11, 1, 9);
      final stuckDraft = OfflineEntityDraft(
        draftId: OfflineEntityDraft.createDraftIdFor(
          entityType: DraftEntityType.laboratory,
          entityId: 'lab-stuck',
        ),
        ownerUid: 'admin-1',
        entityType: DraftEntityType.laboratory,
        entityId: 'lab-stuck',
        data: const {
          'name': 'Laboratorium Tertunda',
          'code': 'LAB-TER-01',
          'location': 'Gedung C',
          'description': 'Sedang sinkron lalu force stop',
          'status': 'active',
        },
        createdAt: now,
        updatedAt: now,
        syncStatus: DraftSyncStatus.syncing,
      );

      await draftStore.saveDraft('admin-1', stuckDraft);

      // Simulate app process termination & restart:
      SharedPreferencesAdminEntityDraftStore.resetRecoveryStateForTesting();
      final restartedStore = SharedPreferencesAdminEntityDraftStore();

      final recoveredList = await restartedStore.listDrafts('admin-1');
      expect(recoveredList, hasLength(1));
      expect(recoveredList.first.syncStatus, DraftSyncStatus.pending);
      expect(
        recoveredList.first.lastError,
        contains('Sinkronisasi sebelumnya terhenti'),
      );
    });

    test('Serializes concurrent saveDraft calls without lost updates', () async {
      final now = DateTime.utc(2026, 11, 1, 9);
      final draftsToSave = List.generate(
        8,
        (index) => OfflineEntityDraft(
          draftId: OfflineEntityDraft.createDraftIdFor(
            entityType: DraftEntityType.asset,
            entityId: 'asset-$index',
          ),
          ownerUid: 'admin-concurrent',
          entityType: DraftEntityType.asset,
          entityId: 'asset-$index',
          data: {
            'name': 'Aset Konkuren $index',
            'code': 'AST-00$index',
            'stock': index + 1,
          },
          createdAt: now,
          updatedAt: now.add(Duration(seconds: index)),
        ),
      );

      // Fire all 8 read-modify-write operations concurrently without awaiting each one sequentially:
      await Future.wait(
        draftsToSave.map((d) => draftStore.saveDraft('admin-concurrent', d)),
      );

      final persisted = await draftStore.listDrafts('admin-concurrent');
      expect(persisted, hasLength(8));
      expect(
        persisted.map((d) => d.entityId).toSet(),
        equals({for (var i = 0; i < 8; i++) 'asset-$i'}),
      );
    });

    test('Handles malformed storage and corrupted individual entries safely without losing valid drafts', () async {
      final rawPrefs = SharedPreferencesAsync();
      final key = 'offline_admin_entity_drafts_v1/admin-corrupt';
      final validDraftJson = OfflineEntityDraft(
        draftId: 'laboratory:edit:lab-valid',
        ownerUid: 'admin-corrupt',
        entityType: DraftEntityType.laboratory,
        entityId: 'lab-valid',
        data: const {'name': 'Lab Valid', 'code': 'LAB-VAL-01'},
        createdAt: DateTime.utc(2026, 11, 1, 9),
        updatedAt: DateTime.utc(2026, 11, 1, 9),
      ).toJson();

      // 1. Partial entry corruption inside valid outer JSON map:
      await rawPrefs.setString(
        key,
        jsonEncode({
          'laboratory:edit:lab-valid': validDraftJson,
          'corrupted:entry': {'draftId': 12345, 'entityType': 'unknown_type'},
        }),
      );

      SharedPreferencesAdminEntityDraftStore.resetRecoveryStateForTesting();
      final loadedPartial = await draftStore.listDrafts('admin-corrupt');
      expect(loadedPartial, hasLength(1));
      expect(loadedPartial.first.draftId, 'laboratory:edit:lab-valid');

      // 2. Completely malformed JSON string:
      await rawPrefs.setString(key, '{not-valid-json');
      SharedPreferencesAdminEntityDraftStore.resetRecoveryStateForTesting();
      final loadedMalformed = await draftStore.listDrafts('admin-corrupt');
      expect(loadedMalformed, isEmpty);
    });
  });

  group('Task C — Conflict Detection & Atomic Resolution (Laboratory & Asset)', () {
    late LaboratoryService labService;
    late AssetService assetService;

    setUp(() {
      final baselineTs = Timestamp.fromDate(DateTime.utc(2026, 10, 31, 8));
      firestore.seedDoc('laboratories', 'lab-1', {
        'name': 'Laboratorium Komputer',
        'code': 'LAB-KOM-01',
        'description': 'Praktikum Dasar',
        'location': 'Gedung Lama',
        'status': 'active',
        'createdAt': baselineTs,
        'updatedAt': baselineTs,
      });

      firestore.seedDoc('assets', 'asset-1', {
        'labId': 'lab-1',
        'code': 'KOM-PC-001',
        'name': 'PC Workstation 01',
        'category': 'Komputer',
        'description': 'Intel i7',
        'location': 'Meja 01',
        'stock': 5,
        'status': 'available',
        'condition': 'good',
        'qrValue': 'asset:asset-1',
        'imageUrl': '',
        'createdAt': baselineTs,
        'updatedAt': baselineTs,
      });

      labService = LaboratoryService(firestore: firestore);
      assetService = AssetService(firestore: firestore);
    });

    test('Scenario 1: No server changes -> updates cleanly with only locally changed fields', () async {
      final baseline = <String, Object?>{
        'name': 'Laboratorium Komputer',
        'code': 'LAB-KOM-01',
        'description': 'Praktikum Dasar',
        'location': 'Gedung Lama',
        'status': 'active',
      };

      final applied = await labService.updateLaboratory(
        laboratoryId: 'lab-1',
        name: 'Laboratorium Komputer Lanjut',
        code: 'LAB-KOM-01',
        description: 'Praktikum Dasar',
        location: 'Gedung Lama',
        status: 'active',
        baselineData: baseline,
      );

      expect(applied.keys.toSet(), {'name', 'updatedAt'});
      expect(
        firestore.peekDoc('laboratories', 'lab-1')!['name'],
        'Laboratorium Komputer Lanjut',
      );
    });

    test('Scenario 2 (Case 1 — Disjoint changes): Local changes name, Server changes location -> safely merges both without overwriting server location', () async {
      final baseline = <String, Object?>{
        'name': 'Laboratorium Komputer',
        'code': 'LAB-KOM-01',
        'description': 'Praktikum Dasar',
        'location': 'Gedung Lama',
        'status': 'active',
      };

      // User B updates location on server while User A is offline:
      firestore.seedDoc('laboratories', 'lab-1', {
        ...firestore.peekDoc('laboratories', 'lab-1')!,
        'location': 'Gedung Baru Lantai 4',
      });

      // User A syncs draft where only `name` was modified from baseline:
      final applied = await labService.updateLaboratory(
        laboratoryId: 'lab-1',
        name: 'Laboratorium AI & Komputasi',
        code: 'LAB-KOM-01',
        description: 'Praktikum Dasar',
        location: 'Gedung Lama', // User A's form still had baseline location
        status: 'active',
        baselineData: baseline,
      );

      expect(applied.keys.toSet(), {'name', 'updatedAt'});
      final finalDoc = firestore.peekDoc('laboratories', 'lab-1')!;
      expect(finalDoc['name'], 'Laboratorium AI & Komputasi');
      // Server's disjoint change to location MUST be preserved!
      expect(finalDoc['location'], 'Gedung Baru Lantai 4');
    });

    test('Scenario 3 (Case 2 — Same-field conflict): Local and Server both change name -> throws ConflictDetectedException', () async {
      final baseline = <String, Object?>{
        'name': 'Laboratorium Komputer',
        'code': 'LAB-KOM-01',
        'description': 'Praktikum Dasar',
        'location': 'Gedung Lama',
        'status': 'active',
      };

      // Server changes `name` to 'Laboratorium Jaringan'
      firestore.seedDoc('laboratories', 'lab-1', {
        ...firestore.peekDoc('laboratories', 'lab-1')!,
        'name': 'Laboratorium Jaringan',
      });

      ConflictDetectedException? caught;
      try {
        await labService.updateLaboratory(
          laboratoryId: 'lab-1',
          name: 'Laboratorium IoT',
          code: 'LAB-KOM-01',
          description: 'Praktikum Dasar',
          location: 'Gedung Lama',
          status: 'active',
          baselineData: baseline,
        );
      } on ConflictDetectedException catch (e) {
        caught = e;
      }

      expect(caught, isNotNull);
      expect(caught!.analysis.hasConflict, isTrue);
      expect(caught.analysis.conflicts.keys, contains('name'));
      expect(
        caught.analysis.conflicts['name']!.baselineValue,
        'Laboratorium Komputer',
      );
      expect(caught.analysis.conflicts['name']!.localValue, 'Laboratorium IoT');
      expect(
        caught.analysis.conflicts['name']!.serverValue,
        'Laboratorium Jaringan',
      );
      expect(firestore.writeCountForCollection('laboratories'), 0);
    });

    test('Scenario 4: Multi-field conflict on Asset & User chooses Local, Server, or Manual resolution', () async {
      final baseline = <String, Object?>{
        'code': 'KOM-PC-001',
        'name': 'PC Workstation 01',
        'category': 'Komputer',
        'description': 'Intel i7',
        'location': 'Meja 01',
        'stock': 5,
        'status': 'available',
        'condition': 'good',
        'imageUrl': '',
      };

      // Server modifies `name`, `stock`, and `description` (disjoint server change)
      firestore.seedDoc('assets', 'asset-1', {
        ...firestore.peekDoc('assets', 'asset-1')!,
        'name': 'PC Server Edition',
        'stock': 8,
        'description': 'Intel Xeon Server',
      });

      // Local modifies `name` (conflict), `stock` (conflict), and `location` (disjoint local change)
      ConflictDetectedException? conflict;
      try {
        await assetService.updateAsset(
          assetId: 'asset-1',
          code: 'KOM-PC-001',
          name: 'PC Praktikum Grafis',
          category: 'Komputer',
          description: 'Intel i7',
          location: 'Meja 09',
          stock: 12,
          status: 'available',
          condition: 'good',
          imageUrl: '',
          baselineData: baseline,
        );
      } on ConflictDetectedException catch (e) {
        conflict = e;
      }

      expect(conflict, isNotNull);
      expect(conflict!.analysis.conflicts.keys.toSet(), {'name', 'stock'});
      expect(conflict.analysis.disjointLocalFields, {'location'});
      expect(conflict.analysis.disjointServerFields, {'description'});

      // User resolves:
      // - `name`: useLocal ('PC Praktikum Grafis')
      // - `stock`: useServer (8)
      final decisions = <String, ConflictResolutionDecision>{
        'name': const ConflictResolutionDecision.useLocal(),
        'stock': const ConflictResolutionDecision.useServer(),
      };

      await assetService.updateAsset(
        assetId: 'asset-1',
        code: 'KOM-PC-001',
        name: 'PC Praktikum Grafis',
        category: 'Komputer',
        description: 'Intel i7',
        location: 'Meja 09',
        stock: 12,
        status: 'available',
        condition: 'good',
        imageUrl: '',
        baselineData: baseline,
        conflictDecisions: decisions,
      );

      final updatedDoc = firestore.peekDoc('assets', 'asset-1')!;
      expect(updatedDoc['name'], 'PC Praktikum Grafis'); // local choice
      expect(updatedDoc['stock'], 8); // server choice
      expect(updatedDoc['location'], 'Meja 09'); // disjoint local preserved
      expect(
        updatedDoc['description'],
        'Intel Xeon Server',
      ); // disjoint server preserved

      // Also test manual resolution on Laboratory:
      firestore.seedDoc('laboratories', 'lab-1', {
        ...firestore.peekDoc('laboratories', 'lab-1')!,
        'name': 'Laboratorium Server',
      });
      final labBaseline = <String, Object?>{
        'name': 'Laboratorium Komputer',
        'code': 'LAB-KOM-01',
        'description': 'Praktikum Dasar',
        'location': 'Gedung Lama',
        'status': 'active',
      };
      await labService.updateLaboratory(
        laboratoryId: 'lab-1',
        name: 'Laboratorium Lokal',
        code: 'LAB-KOM-01',
        description: 'Praktikum Dasar',
        location: 'Gedung Lama',
        status: 'active',
        baselineData: labBaseline,
        conflictDecisions: {
          'name': const ConflictResolutionDecision.manual(
            'Laboratorium Gabungan Manual',
          ),
        },
      );
      expect(
        firestore.peekDoc('laboratories', 'lab-1')!['name'],
        'Laboratorium Gabungan Manual',
      );
    });

    test('Scenario 5: New conflict appears during transaction commit -> aborts and throws updated ConflictDetectedException', () async {
      final baseline = <String, Object?>{
        'name': 'Laboratorium Komputer',
        'code': 'LAB-KOM-01',
        'description': 'Praktikum Dasar',
        'location': 'Gedung Lama',
        'status': 'active',
      };

      // Initially `name` had a conflict that the user resolved,
      // but right when transaction runs, another user modified `location` on the server
      // while local also modified `location`!
      firestore.onTransactionAttempt = (attempt) {
        if (attempt == 1) {
          firestore.seedDoc('laboratories', 'lab-1', {
            ...firestore.peekDoc('laboratories', 'lab-1')!,
            'name': 'Laboratorium Jaringan',
            'location': 'Gedung Server Dadakan',
          });
        }
      };

      ConflictDetectedException? newConflict;
      try {
        await labService.updateLaboratory(
          laboratoryId: 'lab-1',
          name: 'Laboratorium IoT',
          code: 'LAB-KOM-01',
          description: 'Praktikum Dasar',
          location: 'Gedung Lokal Baru',
          status: 'active',
          baselineData: baseline,
          // User only resolved `name` previously, unaware of the new `location` conflict:
          conflictDecisions: {
            'name': const ConflictResolutionDecision.useLocal(),
          },
        );
      } on ConflictDetectedException catch (e) {
        newConflict = e;
      }

      expect(newConflict, isNotNull);
      expect(newConflict!.analysis.conflicts.keys, containsAll(['name', 'location']));
      // Transaction aborted without writing partial data:
      expect(firestore.writeCountForCollection('laboratories'), 0);
    });

    test('Scenario 6: Transaction failure preserves offline draft for retry', () async {
      final now = DateTime.utc(2026, 11, 1, 9);
      final draft = OfflineEntityDraft(
        draftId: OfflineEntityDraft.createDraftIdFor(
          entityType: DraftEntityType.laboratory,
          entityId: 'lab-1',
        ),
        ownerUid: 'superadmin-1',
        entityType: DraftEntityType.laboratory,
        entityId: 'lab-1',
        data: const {
          'name': 'Laboratorium Offline Edit',
          'code': 'LAB-KOM-01',
          'description': 'Praktikum Dasar',
          'location': 'Gedung Lama',
          'status': 'active',
        },
        baselineData: const {
          'name': 'Laboratorium Komputer',
          'code': 'LAB-KOM-01',
          'description': 'Praktikum Dasar',
          'location': 'Gedung Lama',
          'status': 'active',
        },
        createdAt: now,
        updatedAt: now,
      );
      await draftStore.saveDraft('superadmin-1', draft);

      firestore.failWritesWithError = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );

      await expectLater(
        () => labService.updateLaboratory(
          laboratoryId: 'lab-1',
          name: 'Laboratorium Offline Edit',
          code: 'LAB-KOM-01',
          description: 'Praktikum Dasar',
          location: 'Gedung Lama',
          status: 'active',
          baselineData: draft.baselineData,
        ),
        throwsA(isA<LaboratoryException>()),
      );

      // Mark draft failed as the sync handler does and verify draft is still preserved:
      await draftStore.saveDraft(
        'superadmin-1',
        draft.copyWith(
          syncStatus: DraftSyncStatus.failed,
          lastError: 'Koneksi internet tidak stabil.',
        ),
      );

      final preserved = await draftStore.readDraft(
        'superadmin-1',
        draft.draftId,
      );
      expect(preserved, isNotNull);
      expect(preserved!.syncStatus, DraftSyncStatus.failed);
      expect(preserved.data['name'], 'Laboratorium Offline Edit');
    });

    test('Scenario 7: Same-field server value changes AGAIN after user chooses resolution -> aborts stale decision and throws updated ConflictDetectedException', () async {
      final baseline = <String, Object?>{
        'name': 'Laboratorium Komputer',
        'code': 'LAB-KOM-01',
        'description': 'Praktikum Dasar',
        'location': 'Gedung Lama',
        'status': 'active',
      };

      // User initially saw server value 'Laboratorium Jaringan V1' and chose `useLocal` (or `useServer`),
      // but before the transaction commits, User C updates the SAME `name` field on server to 'Laboratorium Jaringan V2'!
      firestore.seedDoc('laboratories', 'lab-1', {
        ...firestore.peekDoc('laboratories', 'lab-1')!,
        'name': 'Laboratorium Jaringan V2',
      });

      final staleDecisions = <String, ConflictResolutionDecision>{
        'name': const ConflictResolutionDecision.useLocal(
          expectedServerValue: 'Laboratorium Jaringan V1',
          hasExpectedServerValue: true,
        ),
      };

      ConflictDetectedException? staleConflict;
      try {
        await labService.updateLaboratory(
          laboratoryId: 'lab-1',
          name: 'Laboratorium IoT Lokal',
          code: 'LAB-KOM-01',
          description: 'Praktikum Dasar',
          location: 'Gedung Lama',
          status: 'active',
          baselineData: baseline,
          conflictDecisions: staleDecisions,
        );
      } on ConflictDetectedException catch (e) {
        staleConflict = e;
      }

      expect(staleConflict, isNotNull);
      expect(
        staleConflict!.analysis.conflicts['name']?.serverValue,
        'Laboratorium Jaringan V2',
      );
      // Stale decision MUST NOT be applied to Firestore:
      expect(firestore.writeCountForCollection('laboratories'), 0);
      expect(
        firestore.peekDoc('laboratories', 'lab-1')!['name'],
        'Laboratorium Jaringan V2',
      );
    });
  });
}
