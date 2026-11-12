import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:labflow/core/session/app_session_manager.dart';
import 'package:labflow/features/asset/data/asset_service.dart';
import 'package:labflow/features/auth/data/auth_service.dart';
import 'package:labflow/features/auth/domain/user_profile.dart';
import 'package:labflow/features/laboratory/data/laboratory_service.dart';
import 'package:labflow/features/laboratory/domain/laboratory.dart';
import 'package:labflow/features/profile/data/profile_edit_service.dart';
import 'package:labflow/features/profile/presentation/cubit/profile_edit_cubit.dart';
import 'package:labflow/features/superadmin/data/activity_log_service.dart';
import 'package:labflow/features/superadmin/data/admin_credential_service.dart';
import 'package:labflow/features/superadmin/data/user_management_service.dart';
import 'package:labflow/features/superadmin/presentation/cubit/laboratory_management_action_cubit.dart';
import 'package:labflow/features/superadmin/presentation/cubit/user_management_action_cubit.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/fake_firestore.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _MockAdminCredentialService extends Mock
    implements AdminCredentialService {}

class _MemorySessionStorage implements AppSessionStorage {
  AppSession? session;

  @override
  Future<AppSession?> read() async => session;

  @override
  Future<void> write(AppSession value) async => session = value;

  @override
  Future<void> clear() async => session = null;
}

void main() {
  late DateTime currentClock;
  late FakeMemoryFirestore firestore;
  late _MockFirebaseAuth firebaseAuth;
  late _MockUser authUser;
  late _MemorySessionStorage sessionStorage;
  late AppSessionManager sessionManager;

  setUp(() async {
    currentClock = DateTime.utc(2026, 11, 1, 9, 0, 0);
    firestore = FakeMemoryFirestore(clock: () => currentClock);
    firebaseAuth = _MockFirebaseAuth();
    authUser = _MockUser();
    when(() => authUser.uid).thenReturn('superadmin-1');
    when(() => authUser.email).thenReturn('superadmin@labflow.test');
    when(() => firebaseAuth.currentUser).thenReturn(authUser);
    when(() => firebaseAuth.signOut()).thenAnswer((_) async {});

    sessionStorage = _MemorySessionStorage();
    sessionManager = AppSessionManager(
      storage: sessionStorage,
      now: () => currentClock,
    );
    await sessionManager.start('superadmin-1');
    AuthService.clearProfileCache();

    firestore.seedDoc('users', 'superadmin-1', {
      'uid': 'superadmin-1',
      'email': 'superadmin@labflow.test',
      'fullName': 'Superadmin Utama',
      'role': 'superadmin',
      'status': 'active',
    });
  });

  group('1. LaboratoryService & LaboratoryManagementActionCubit No-Op Verification', () {
    late LaboratoryService labService;
    late ActivityLogService activityLogService;
    late LaboratoryManagementActionCubit labCubit;
    late Timestamp initialTimestamp;

    setUp(() {
      initialTimestamp = Timestamp.fromDate(DateTime.utc(2026, 10, 30, 8));
      firestore.seedDoc('laboratories', 'lab-iot', {
        'name': 'Laboratorium IoT',
        'code': 'LAB-IOT-01',
        'description': 'Deskripsi awal',
        'location': 'Gedung A Lantai 2',
        'status': 'active',
        'createdAt': initialTimestamp,
        'updatedAt': initialTimestamp,
      });

      labService = LaboratoryService(firestore: firestore);
      activityLogService = ActivityLogService(
        firestore: firestore,
        firebaseAuth: firebaseAuth,
      );
      labCubit = LaboratoryManagementActionCubit(
        labService,
        activityLogService,
      );
    });

    tearDown(() async => labCubit.close());

    test('No changes -> 0 Firestore writes, no updatedAt change, no Activity Log', () async {
      await labService.updateLaboratory(
        laboratoryId: 'lab-iot',
        name: '  Laboratorium IoT  ',
        code: 'lab-iot-01',
        description: 'Deskripsi awal',
        location: 'Gedung A Lantai 2',
        status: 'active',
      );

      expect(firestore.totalWriteCount, 0);
      expect(
        firestore.peekDoc('laboratories', 'lab-iot')!['updatedAt'],
        initialTimestamp,
      );

      final original = const Laboratory(
        id: 'lab-iot',
        name: 'Laboratorium IoT',
        code: 'LAB-IOT-01',
        description: 'Deskripsi awal',
        location: 'Gedung A Lantai 2',
        status: 'active',
      );

      await labCubit.updateLaboratory(
        laboratoryId: 'lab-iot',
        name: 'Laboratorium IoT',
        code: 'LAB-IOT-01',
        description: 'Deskripsi awal',
        location: 'Gedung A Lantai 2',
        status: 'active',
        original: original,
      );

      expect(firestore.writeCountForCollection('laboratories'), 0);
      expect(firestore.writeCountForCollection('activity_logs'), 0);
    });

    test('One field changed -> 1 update with only changed field + updatedAt, 1 Activity Log', () async {
      currentClock = DateTime.utc(2026, 11, 1, 10, 0, 0);
      final original = const Laboratory(
        id: 'lab-iot',
        name: 'Laboratorium IoT',
        code: 'LAB-IOT-01',
        description: 'Deskripsi awal',
        location: 'Gedung A Lantai 2',
        status: 'active',
      );

      await labCubit.updateLaboratory(
        laboratoryId: 'lab-iot',
        name: 'Laboratorium IoT',
        code: 'LAB-IOT-01',
        description: 'Deskripsi awal',
        location: 'Gedung B Lantai 3',
        status: 'active',
        original: original,
      );

      final labWrites = firestore.writesFor('laboratories', 'lab-iot');
      expect(labWrites.length, 1);
      expect(labWrites.single.payload.keys.toSet(), {'location', 'updatedAt'});
      expect(labWrites.single.payload['location'], 'Gedung B Lantai 3');
      expect(
        firestore.peekDoc('laboratories', 'lab-iot')!['updatedAt'],
        Timestamp.fromDate(currentClock),
      );
      expect(firestore.writeCountForCollection('activity_logs'), 1);
    });

    test('Multiple fields changed -> 1 update with exact changed payload', () async {
      await labService.updateLaboratory(
        laboratoryId: 'lab-iot',
        name: 'Laboratorium IoT Terpadu',
        code: 'LAB-IOT-02',
        description: 'Deskripsi awal',
        location: 'Gedung A Lantai 2',
        status: 'inactive',
      );

      final labWrites = firestore.writesFor('laboratories', 'lab-iot');
      expect(labWrites.length, 1);
      expect(
        labWrites.single.payload.keys.toSet(),
        {'name', 'code', 'status', 'updatedAt'},
      );
      expect(labWrites.single.payload.containsKey('description'), isFalse);
      expect(labWrites.single.payload.containsKey('location'), isFalse);
    });

    test('Double submission -> prevents duplicate writes and duplicate Activity Logs', () async {
      final original = const Laboratory(
        id: 'lab-iot',
        name: 'Laboratorium IoT',
        code: 'LAB-IOT-01',
        description: 'Deskripsi awal',
        location: 'Gedung A Lantai 2',
        status: 'active',
      );

      final firstCall = labCubit.updateLaboratory(
        laboratoryId: 'lab-iot',
        name: 'Laboratorium IoT Baru',
        code: 'LAB-IOT-01',
        description: 'Deskripsi awal',
        location: 'Gedung A Lantai 2',
        status: 'active',
        original: original,
      );
      final secondCall = labCubit.updateLaboratory(
        laboratoryId: 'lab-iot',
        name: 'Laboratorium IoT Baru',
        code: 'LAB-IOT-01',
        description: 'Deskripsi awal',
        location: 'Gedung A Lantai 2',
        status: 'active',
        original: original,
      );

      await Future.wait([firstCall, secondCall]);

      expect(firestore.writeCountForCollection('laboratories'), 1);
      expect(firestore.writeCountForCollection('activity_logs'), 1);
    });

    test('Update failure -> error handled cleanly without Activity Log', () async {
      firestore.failWritesWithError = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );

      final original = const Laboratory(
        id: 'lab-iot',
        name: 'Laboratorium IoT',
        code: 'LAB-IOT-01',
        description: 'Deskripsi awal',
        location: 'Gedung A Lantai 2',
        status: 'active',
      );

      await expectLater(
        () => labCubit.updateLaboratory(
          laboratoryId: 'lab-iot',
          name: 'Laboratorium IoT Baru',
          code: 'LAB-IOT-01',
          description: 'Deskripsi awal',
          location: 'Gedung A Lantai 2',
          status: 'active',
          original: original,
        ),
        throwsA(isA<FirebaseException>()),
      );

      expect(firestore.writeCountForCollection('laboratories'), 0);
      expect(firestore.writeCountForCollection('activity_logs'), 0);
      expect(labCubit.state, isFalse);
    });
  });

  group('2. AssetService No-Op Verification', () {
    late AssetService assetService;
    late Timestamp initialTimestamp;

    setUp(() {
      initialTimestamp = Timestamp.fromDate(DateTime.utc(2026, 10, 30, 8));
      firestore.seedDoc('laboratories', 'lab-iot', {
        'name': 'Laboratorium IoT',
        'code': 'LAB-IOT-01',
        'status': 'active',
      });
      firestore.seedDoc('assets', 'asset-1', {
        'labId': 'lab-iot',
        'code': 'IOT-ESP-001',
        'name': 'ESP32 DevKit',
        'category': 'Mikrokontroler',
        'description': 'Board praktikum IoT',
        'location': 'Rak A1',
        'stock': 10,
        'status': 'available',
        'condition': 'good',
        'qrValue': 'asset:asset-1',
        'imageUrl': 'https://example.com/esp32.jpg',
        'createdAt': initialTimestamp,
        'updatedAt': initialTimestamp,
      });

      assetService = AssetService(firestore: firestore);
    });

    test('No changes -> 0 Firestore writes and no timestamp change', () async {
      await assetService.updateAsset(
        assetId: 'asset-1',
        code: ' iot-esp-001 ',
        name: ' ESP32 DevKit ',
        category: 'Mikrokontroler',
        description: 'Board praktikum IoT',
        location: 'Rak A1',
        stock: 10,
        status: 'available',
        condition: 'good',
        imageUrl: 'https://example.com/esp32.jpg',
      );

      expect(firestore.writeCountForCollection('assets'), 0);
      expect(
        firestore.peekDoc('assets', 'asset-1')!['updatedAt'],
        initialTimestamp,
      );
    });

    test('One field changed -> 1 update with only changed field + updatedAt', () async {
      currentClock = DateTime.utc(2026, 11, 1, 11, 0, 0);
      await assetService.updateAsset(
        assetId: 'asset-1',
        code: 'IOT-ESP-001',
        name: 'ESP32 DevKit',
        category: 'Mikrokontroler',
        description: 'Board praktikum IoT',
        location: 'Rak A1',
        stock: 15,
        status: 'available',
        condition: 'good',
        imageUrl: 'https://example.com/esp32.jpg',
      );

      final writes = firestore.writesFor('assets', 'asset-1');
      expect(writes.length, 1);
      expect(writes.single.payload.keys.toSet(), {'stock', 'updatedAt'});
      expect(writes.single.payload['stock'], 15);
      expect(
        firestore.peekDoc('assets', 'asset-1')!['updatedAt'],
        Timestamp.fromDate(currentClock),
      );
    });

    test('Multiple fields changed -> 1 update with exact changed fields', () async {
      await assetService.updateAsset(
        assetId: 'asset-1',
        code: 'IOT-ESP-002',
        name: 'ESP32-S3 DevKit',
        category: 'Mikrokontroler',
        description: 'Board praktikum IoT',
        location: 'Rak B2',
        stock: 10,
        status: 'maintenance',
        condition: 'minor_damage',
        imageUrl: 'https://example.com/esp32.jpg',
      );

      final writes = firestore.writesFor('assets', 'asset-1');
      expect(writes.length, 1);
      expect(
        writes.single.payload.keys.toSet(),
        {'code', 'name', 'location', 'status', 'condition', 'updatedAt'},
      );
      expect(writes.single.payload.containsKey('stock'), isFalse);
      expect(writes.single.payload.containsKey('category'), isFalse);
    });
  });

  group('3. ProfileEditService & ProfileEditCubit No-Op Verification', () {
    late AuthService authService;
    late ProfileEditService profileService;
    late ProfileEditCubit profileCubit;

    setUp(() async {
      when(() => authUser.uid).thenReturn('student-1');
      when(() => authUser.email).thenReturn('student@labflow.test');
      await sessionManager.start('student-1');

      firestore.seedDoc('users', 'student-1', {
        'uid': 'student-1',
        'email': 'student@labflow.test',
        'fullName': 'Budi Santoso',
        'role': 'student',
        'status': 'active',
        'phoneNumber': '08123456789',
        'nim': '230101001',
        'studyProgram': 'Informatika',
        'semester': 5,
      });

      authService = AuthService(
        firebaseAuth: firebaseAuth,
        firestore: firestore,
        sessionManager: sessionManager,
      );
      profileService = ProfileEditService(
        authService: authService,
        firestore: firestore,
      );
      profileCubit = ProfileEditCubit(profileService);
    });

    tearDown(() async => profileCubit.close());

    test('No changes in service and cubit -> 0 writes', () async {
      await profileService.saveProfile(
        fullName: '  Budi Santoso  ',
        phoneNumber: '08123456789',
        nim: '230101001',
        studyProgram: 'Informatika',
        semester: 5,
        nip: '',
        nidn: '',
      );

      expect(firestore.writeCountForCollection('users'), 0);

      await profileCubit.load();
      expect(profileCubit.state.hasChanges, isFalse);
      await profileCubit.save();
      expect(firestore.writeCountForCollection('users'), 0);
    });

    test('Single field changed -> 1 update containing only that field and refreshes cache', () async {
      await profileCubit.load();
      profileCubit.setSemester(6);
      expect(profileCubit.state.hasChanges, isTrue);

      await profileCubit.save();

      final writes = firestore.writesFor('users', 'student-1');
      expect(writes.length, 1);
      expect(writes.single.payload, {'semester': 6});
      expect(AuthService.debugCachedProfile('student-1')?.semester, 6);
    });

    test('Double submission in ProfileEditCubit -> only 1 write executed', () async {
      await profileCubit.load();
      profileCubit.setFullName('Budi Santoso Wijaya');

      final first = profileCubit.save();
      final second = profileCubit.save();
      await Future.wait([first, second]);

      expect(firestore.writeCountForCollection('users'), 1);
    });
  });

  group('4. UserManagementService & UserManagementActionCubit No-Op Verification', () {
    late UserManagementService userService;
    late ActivityLogService activityLogService;
    late UserManagementActionCubit userCubit;
    late Timestamp initialTimestamp;

    setUp(() {
      initialTimestamp = Timestamp.fromDate(DateTime.utc(2026, 10, 30, 8));
      firestore.seedDoc('users', 'student-target', {
        'uid': 'student-target',
        'email': 'target@labflow.test',
        'fullName': 'Siti Aminah',
        'role': 'student',
        'status': 'active',
        'phoneNumber': '08111222333',
        'nim': '230102002',
        'studyProgram': 'Sistem Informasi',
        'semester': 3,
        'updatedAt': initialTimestamp,
      });

      userService = UserManagementService(
        firestore: firestore,
        firebaseAuth: firebaseAuth,
        credentialService: _MockAdminCredentialService(),
      );
      activityLogService = ActivityLogService(
        firestore: firestore,
        firebaseAuth: firebaseAuth,
      );
      userCubit = UserManagementActionCubit(userService, activityLogService);
    });

    tearDown(() async => userCubit.close());

    test('No changes -> 0 writes, no updatedAt change, no Activity Log', () async {
      final originalProfile = const UserProfile(
        uid: 'student-target',
        email: 'target@labflow.test',
        fullName: 'Siti Aminah',
        role: 'student',
        status: 'active',
        phoneNumber: '08111222333',
        nim: '230102002',
        studyProgram: 'Sistem Informasi',
        semester: 3,
      );

      await userCubit.updateUser(
        userId: 'student-target',
        fullName: '  Siti Aminah ',
        role: 'student',
        status: 'active',
        originalFullName: 'Siti Aminah',
        originalRole: 'student',
        email: 'target@labflow.test',
        phoneNumber: '08111222333',
        nim: '230102002',
        studyProgram: 'Sistem Informasi',
        semester: 3,
        originalProfile: originalProfile,
      );

      expect(firestore.writeCountForCollection('users'), 0);
      expect(firestore.writeCountForCollection('activity_logs'), 0);

      // Even without originalProfile passed to cubit, service-level diff returns false:
      await userCubit.updateUser(
        userId: 'student-target',
        fullName: 'Siti Aminah',
        role: 'student',
        status: 'active',
        originalFullName: 'Siti Aminah',
        originalRole: 'student',
        email: 'target@labflow.test',
        phoneNumber: '08111222333',
        nim: '230102002',
        studyProgram: 'Sistem Informasi',
        semester: 3,
      );

      expect(firestore.writeCountForCollection('users'), 0);
      expect(firestore.writeCountForCollection('activity_logs'), 0);
      expect(
        firestore.peekDoc('users', 'student-target')!['updatedAt'],
        initialTimestamp,
      );
    });

    test('No-op activateUser when already active -> 0 writes, 0 Activity Logs', () async {
      await userCubit.setUserStatus(
        userId: 'student-target',
        fullName: 'Siti Aminah',
        email: 'target@labflow.test',
        suspend: false,
      );

      expect(firestore.writeCountForCollection('users'), 0);
      expect(firestore.writeCountForCollection('activity_logs'), 0);
    });

    test('One field changed -> 1 update with only changed field + updatedAt, 1 Activity Log', () async {
      await userCubit.updateUser(
        userId: 'student-target',
        fullName: 'Siti Aminah',
        role: 'student',
        status: 'active',
        originalFullName: 'Siti Aminah',
        originalRole: 'student',
        email: 'target@labflow.test',
        phoneNumber: '08111222333',
        nim: '230102002',
        studyProgram: 'Sistem Informasi',
        semester: 4,
      );

      final writes = firestore.writesFor('users', 'student-target');
      expect(writes.length, 1);
      expect(writes.single.payload.keys.toSet(), {'semester', 'updatedAt'});
      expect(writes.single.payload['semester'], 4);
      expect(firestore.writeCountForCollection('activity_logs'), 1);
    });
  });
}
