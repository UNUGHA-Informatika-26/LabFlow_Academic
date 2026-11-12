import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'conflict_resolution.dart';

enum DraftEntityType {
  laboratory('laboratory'),
  asset('asset');

  const DraftEntityType(this.value);
  final String value;

  static DraftEntityType fromString(String raw) => switch (raw.trim()) {
    'laboratory' => DraftEntityType.laboratory,
    'asset' => DraftEntityType.asset,
    _ => throw FormatException('Tipe entitas draft tidak dikenali: $raw'),
  };
}

enum DraftSyncStatus {
  pending('pending'),
  conflict('conflict'),
  syncing('syncing'),
  failed('failed');

  const DraftSyncStatus(this.value);
  final String value;

  static DraftSyncStatus fromString(String raw) => switch (raw.trim()) {
    'pending' => DraftSyncStatus.pending,
    'conflict' => DraftSyncStatus.conflict,
    'syncing' => DraftSyncStatus.syncing,
    'failed' => DraftSyncStatus.failed,
    _ => DraftSyncStatus.pending,
  };
}

class OfflineEntityDraft {
  const OfflineEntityDraft({
    required this.draftId,
    required this.ownerUid,
    required this.entityType,
    required this.data,
    required this.createdAt,
    required this.updatedAt,
    this.entityId,
    this.baselineData,
    this.baselineUpdatedAt,
    this.syncStatus = DraftSyncStatus.pending,
    this.lastError,
    this.conflicts = const <String, FieldConflict>{},
  });

  final String draftId;
  final String ownerUid;
  final DraftEntityType entityType;
  final String? entityId;
  final Map<String, Object?> data;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, Object?>? baselineData;
  final DateTime? baselineUpdatedAt;
  final DraftSyncStatus syncStatus;
  final String? lastError;
  final Map<String, FieldConflict> conflicts;

  bool get isCreateDraft => entityId == null || entityId!.trim().isEmpty;
  bool get isEditDraft => !isCreateDraft;

  static String createDraftIdFor({
    required DraftEntityType entityType,
    String? entityId,
    String? customKey,
  }) {
    final cleanEntityId = entityId?.trim();
    if (cleanEntityId != null && cleanEntityId.isNotEmpty) {
      return '${entityType.value}:edit:$cleanEntityId';
    }
    final suffix = (customKey?.trim().isNotEmpty ?? false)
        ? customKey!.trim()
        : 'new';
    return '${entityType.value}:create:$suffix';
  }

  /// Menghapus key sensitif seperti password, token, atau secret
  /// agar tidak pernah tersimpan di penyimpanan lokal.
  static Map<String, Object?> sanitizeData(Map<String, Object?> input) {
    const forbiddenSubstrings = <String>[
      'password',
      'token',
      'secret',
      'credential',
      'apikey',
      'api_key',
      'privatekey',
    ];
    final sanitized = <String, Object?>{};
    for (final entry in input.entries) {
      final lowerKey = entry.key.toLowerCase();
      final isSensitive = forbiddenSubstrings.any(lowerKey.contains);
      if (!isSensitive) {
        sanitized[entry.key] = entry.value;
      }
    }
    return Map.unmodifiable(sanitized);
  }

  OfflineEntityDraft copyWith({
    String? draftId,
    String? ownerUid,
    DraftEntityType? entityType,
    String? entityId,
    Map<String, Object?>? data,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, Object?>? baselineData,
    DateTime? baselineUpdatedAt,
    DraftSyncStatus? syncStatus,
    String? lastError,
    bool clearError = false,
    Map<String, FieldConflict>? conflicts,
  }) {
    return OfflineEntityDraft(
      draftId: draftId ?? this.draftId,
      ownerUid: ownerUid ?? this.ownerUid,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      data: data != null ? sanitizeData(data) : this.data,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      baselineData: baselineData != null
          ? sanitizeData(baselineData)
          : this.baselineData,
      baselineUpdatedAt: baselineUpdatedAt ?? this.baselineUpdatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      lastError: clearError ? null : (lastError ?? this.lastError),
      conflicts: conflicts ?? this.conflicts,
    );
  }

  Map<String, Object?> toJson() => {
    'draftId': draftId,
    'ownerUid': ownerUid,
    'entityType': entityType.value,
    'entityId': entityId,
    'data': sanitizeData(data),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'baselineData': baselineData == null ? null : sanitizeData(baselineData!),
    'baselineUpdatedAt': baselineUpdatedAt?.toUtc().toIso8601String(),
    'syncStatus': syncStatus.value,
    'lastError': lastError,
    'conflicts': conflicts.map((key, value) => MapEntry(key, value.toJson())),
  };

  factory OfflineEntityDraft.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    final dataMap = rawData is Map
        ? sanitizeData(Map<String, Object?>.from(rawData))
        : const <String, Object?>{};

    final rawBaseline = json['baselineData'];
    final baselineMap = rawBaseline is Map
        ? sanitizeData(Map<String, Object?>.from(rawBaseline))
        : null;

    final rawConflicts = json['conflicts'];
    final parsedConflicts = <String, FieldConflict>{};
    if (rawConflicts is Map) {
      for (final entry in rawConflicts.entries) {
        if (entry.value is Map) {
          parsedConflicts[entry.key.toString()] = FieldConflict.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      }
    }

    final rawBaselineUpdatedAt = json['baselineUpdatedAt'] as String?;

    return OfflineEntityDraft(
      draftId: json['draftId'] as String,
      ownerUid: json['ownerUid'] as String,
      entityType: DraftEntityType.fromString(json['entityType'] as String),
      entityId: json['entityId'] as String?,
      data: dataMap,
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
      baselineData: baselineMap,
      baselineUpdatedAt: rawBaselineUpdatedAt == null
          ? null
          : DateTime.tryParse(rawBaselineUpdatedAt)?.toUtc(),
      syncStatus: DraftSyncStatus.fromString(
        json['syncStatus'] as String? ?? 'pending',
      ),
      lastError: json['lastError'] as String?,
      conflicts: Map.unmodifiable(parsedConflicts),
    );
  }
}

abstract interface class AdminEntityDraftStore {
  Future<List<OfflineEntityDraft>> listDrafts(
    String uid, {
    DraftEntityType? entityType,
  });

  Future<OfflineEntityDraft?> readDraft(String uid, String draftId);

  Future<OfflineEntityDraft?> readDraftForEntity({
    required String uid,
    required DraftEntityType entityType,
    String? entityId,
  });

  Future<void> saveDraft(String uid, OfflineEntityDraft draft);

  Future<void> removeDraft(String uid, String draftId);

  Future<void> clearAllForUser(String uid);
}

class SharedPreferencesAdminEntityDraftStore implements AdminEntityDraftStore {
  SharedPreferencesAdminEntityDraftStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  /// Antrian serialisasi per-UID untuk mencegah lost update pada operasi
  /// read-modify-write konkuren (saveDraft, removeDraft, clearAllForUser),
  /// serta pemulihan satu kali untuk draft yang tertinggal pada status `syncing`
  /// setelah aplikasi dihentikan paksa (restart).
  static final Map<String, Future<void>> _userOperationLocks =
      <String, Future<void>>{};
  static final Set<String> _recoveredUsersInProcess = <String>{};

  /// Mereset state pemulihan in-memory untuk keperluan simulasi restart aplikasi pada pengujian.
  static void resetRecoveryStateForTesting() {
    _recoveredUsersInProcess.clear();
  }

  Future<T> _synchronizedForUser<T>(
    String uid,
    Future<T> Function() action,
  ) {
    final key = uid.trim();
    final previous = _userOperationLocks[key] ?? Future<void>.value();
    final completer = Completer<T>();

    final current = previous.catchError((_) {}).then((_) async {
      try {
        final result = await action();
        completer.complete(result);
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });

    _userOperationLocks[key] = current;
    current.whenComplete(() {
      if (identical(_userOperationLocks[key], current)) {
        _userOperationLocks.remove(key);
      }
    });

    return completer.future;
  }

  String _userKey(String uid) =>
      'offline_admin_entity_drafts_v1/${Uri.encodeComponent(uid.trim())}';

  void _requireMatchingOwner(String uid, OfflineEntityDraft draft) {
    if (uid.trim().isEmpty || draft.ownerUid.trim() != uid.trim()) {
      throw StateError(
        'Akses draft ditolak: UID pemilik draft tidak sesuai dengan sesi aktif.',
      );
    }
  }

  Future<Map<String, OfflineEntityDraft>> _readUserDraftMap(String uid) async {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) {
      return <String, OfflineEntityDraft>{};
    }
    final raw = await _preferences.getString(_userKey(cleanUid));
    if (raw == null || raw.trim().isEmpty) {
      _recoveredUsersInProcess.add(cleanUid);
      return <String, OfflineEntityDraft>{};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        await _preferences.remove(_userKey(cleanUid));
        _recoveredUsersInProcess.add(cleanUid);
        return <String, OfflineEntityDraft>{};
      }
      final needsStartupRecovery = !_recoveredUsersInProcess.contains(cleanUid);
      var hasRecoveredStuckSyncing = false;
      final result = <String, OfflineEntityDraft>{};
      for (final entry in decoded.entries) {
        if (entry.value is Map) {
          try {
            var draft = OfflineEntityDraft.fromJson(
              Map<String, dynamic>.from(entry.value as Map),
            );
            // Hanya kembalikan draft yang benar-benar dimiliki oleh UID ini.
            if (draft.ownerUid.trim() == cleanUid) {
              if (needsStartupRecovery &&
                  draft.syncStatus == DraftSyncStatus.syncing) {
                draft = draft.copyWith(
                  syncStatus: DraftSyncStatus.pending,
                  lastError:
                      'Sinkronisasi sebelumnya terhenti. Silakan kirim ulang draft.',
                );
                hasRecoveredStuckSyncing = true;
              }
              result[draft.draftId] = draft;
            }
          } on Object {
            // Abaikan entri draft individual yang rusak tanpa menghapus draft valid lainnya.
          }
        }
      }
      _recoveredUsersInProcess.add(cleanUid);
      if (hasRecoveredStuckSyncing) {
        try {
          await _writeUserDraftMap(cleanUid, result);
        } on Object {
          // Abaikan kegagalan tulis saat pemulihan pembacaan agar draft tetap dapat dibaca.
        }
      }
      return result;
    } on Object {
      await _preferences.remove(_userKey(cleanUid));
      _recoveredUsersInProcess.add(cleanUid);
      return <String, OfflineEntityDraft>{};
    }
  }

  Future<void> _writeUserDraftMap(
    String uid,
    Map<String, OfflineEntityDraft> drafts,
  ) async {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) return;
    if (drafts.isEmpty) {
      await _preferences.remove(_userKey(cleanUid));
      return;
    }
    final serializable = <String, Object?>{};
    for (final entry in drafts.entries) {
      if (entry.value.ownerUid.trim() == cleanUid) {
        serializable[entry.key] = entry.value.toJson();
      }
    }
    await _preferences.setString(_userKey(cleanUid), jsonEncode(serializable));
  }

  @override
  Future<List<OfflineEntityDraft>> listDrafts(
    String uid, {
    DraftEntityType? entityType,
  }) => _synchronizedForUser(uid, () async {
    final map = await _readUserDraftMap(uid);
    final drafts = map.values
        .where(
          (draft) => entityType == null || draft.entityType == entityType,
        )
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return drafts;
  });

  @override
  Future<OfflineEntityDraft?> readDraft(String uid, String draftId) =>
      _synchronizedForUser(uid, () async {
        final map = await _readUserDraftMap(uid);
        final draft = map[draftId];
        if (draft == null || draft.ownerUid.trim() != uid.trim()) {
          return null;
        }
        return draft;
      });

  @override
  Future<OfflineEntityDraft?> readDraftForEntity({
    required String uid,
    required DraftEntityType entityType,
    String? entityId,
  }) {
    final id = OfflineEntityDraft.createDraftIdFor(
      entityType: entityType,
      entityId: entityId,
    );
    return readDraft(uid, id);
  }

  @override
  Future<void> saveDraft(String uid, OfflineEntityDraft draft) {
    _requireMatchingOwner(uid, draft);
    return _synchronizedForUser(uid, () async {
      final map = await _readUserDraftMap(uid);
      map[draft.draftId] = draft.copyWith(
        data: OfflineEntityDraft.sanitizeData(draft.data),
        baselineData: draft.baselineData == null
            ? null
            : OfflineEntityDraft.sanitizeData(draft.baselineData!),
      );
      await _writeUserDraftMap(uid, map);
    });
  }

  @override
  Future<void> removeDraft(String uid, String draftId) =>
      _synchronizedForUser(uid, () async {
        final map = await _readUserDraftMap(uid);
        if (!map.containsKey(draftId)) return;
        map.remove(draftId);
        await _writeUserDraftMap(uid, map);
      });

  @override
  Future<void> clearAllForUser(String uid) =>
      _synchronizedForUser(uid, () async {
        final cleanUid = uid.trim();
        if (cleanUid.isEmpty) return;
        await _preferences.remove(_userKey(cleanUid));
      });
}
