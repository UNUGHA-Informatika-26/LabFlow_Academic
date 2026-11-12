enum ConflictResolutionChoice { useLocal, useServer, manual }

class FieldConflict {
  const FieldConflict({
    required this.field,
    required this.baselineValue,
    required this.localValue,
    required this.serverValue,
  });

  final String field;
  final Object? baselineValue;
  final Object? localValue;
  final Object? serverValue;

  Map<String, Object?> toJson() => {
    'field': field,
    'baselineValue': baselineValue,
    'localValue': localValue,
    'serverValue': serverValue,
  };

  factory FieldConflict.fromJson(Map<String, dynamic> json) => FieldConflict(
    field: json['field'] as String,
    baselineValue: json['baselineValue'],
    localValue: json['localValue'],
    serverValue: json['serverValue'],
  );
}

class ConflictResolutionDecision {
  const ConflictResolutionDecision({
    required this.choice,
    this.manualValue,
    this.expectedServerValue,
    this.hasExpectedServerValue = false,
  });

  const ConflictResolutionDecision.useLocal({
    this.expectedServerValue,
    this.hasExpectedServerValue = false,
  }) : choice = ConflictResolutionChoice.useLocal,
       manualValue = null;

  const ConflictResolutionDecision.useServer({
    this.expectedServerValue,
    this.hasExpectedServerValue = false,
  }) : choice = ConflictResolutionChoice.useServer,
       manualValue = null;

  const ConflictResolutionDecision.manual(
    this.manualValue, {
    this.expectedServerValue,
    this.hasExpectedServerValue = false,
  }) : choice = ConflictResolutionChoice.manual;

  final ConflictResolutionChoice choice;
  final Object? manualValue;
  final Object? expectedServerValue;
  final bool hasExpectedServerValue;

  /// Memvalidasi apakah nilai di server saat ini masih sama dengan nilai server
  /// yang ditinjau pengguna ketika memilih keputusan resolusi.
  bool matchesServerValue(Object? currentServerValue) {
    if (!hasExpectedServerValue) return true;
    return expectedServerValue == currentServerValue;
  }
}

class ConflictAnalysis {
  const ConflictAnalysis({
    required this.localChangedFields,
    required this.serverChangedFields,
    required this.bothChangedFields,
    required this.unchangedFields,
    required this.disjointLocalFields,
    required this.disjointServerFields,
    required this.conflicts,
    required this.baselineData,
    required this.localData,
    required this.serverData,
  });

  final Set<String> localChangedFields;
  final Set<String> serverChangedFields;
  final Set<String> bothChangedFields;
  final Set<String> unchangedFields;
  final Set<String> disjointLocalFields;
  final Set<String> disjointServerFields;
  final Map<String, FieldConflict> conflicts;
  final Map<String, Object?> baselineData;
  final Map<String, Object?> localData;
  final Map<String, Object?> serverData;

  bool get hasConflict => conflicts.isNotEmpty;

  bool get hasDisjointChanges =>
      !hasConflict &&
      localChangedFields.isNotEmpty &&
      serverChangedFields.isNotEmpty;

  bool get isNoOpAgainstServer {
    for (final entry in localData.entries) {
      if (serverData[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  /// Menghasilkan payload perubahan yang aman untuk diterapkan di server
  /// ketika tidak ada konflik (`!hasConflict`).
  ///
  /// Hanya mengirim field yang berubah secara lokal dan berbeda dari server,
  /// sehingga perubahan disjoint pada server tidak tertimpa.
  Map<String, Object?> buildSafeMergeUpdatePayload() {
    if (hasConflict) {
      throw StateError(
        'Tidak dapat membuat merge otomatis ketika masih terdapat konflik field.',
      );
    }
    final payload = <String, Object?>{};
    for (final field in localChangedFields) {
      final localValue = localData[field];
      final serverValue = serverData[field];
      if (localValue != serverValue) {
        payload[field] = localValue;
      }
    }
    return payload;
  }

  /// Menghasilkan data lokal yang telah digabungkan berdasarkan keputusan
  /// resolusi konflik dari pengguna tanpa mengubah field lain yang tidak disengaja.
  Map<String, Object?> resolveWithDecisions(
    Map<String, ConflictResolutionDecision> decisions,
  ) {
    final resolved = Map<String, Object?>.from(serverData);

    // Pertahankan perubahan lokal yang disjoint (tidak konflik dengan server).
    for (final field in disjointLocalFields) {
      resolved[field] = localData[field];
    }

    // Terapkan keputusan pengguna untuk setiap field yang mengalami konflik.
    for (final entry in conflicts.entries) {
      final field = entry.key;
      final conflict = entry.value;
      final decision = decisions[field];
      if (decision == null) {
        throw ArgumentError(
          'Keputusan resolusi wajib diberikan untuk field "$field".',
        );
      }
      if (!decision.matchesServerValue(conflict.serverValue)) {
        throw StateError(
          'Nilai server untuk field "$field" telah berubah sejak keputusan dibuat.',
        );
      }
      resolved[field] = switch (decision.choice) {
        ConflictResolutionChoice.useLocal => conflict.localValue,
        ConflictResolutionChoice.useServer => conflict.serverValue,
        ConflictResolutionChoice.manual => decision.manualValue,
      };
    }

    return resolved;
  }

  /// Memeriksa apakah terdapat keputusan resolusi yang sudah usang karena
  /// nilai server saat ini berbeda dengan `expectedServerValue` saat pengguna memilih.
  bool hasStaleDecision(Map<String, ConflictResolutionDecision> decisions) {
    for (final entry in conflicts.entries) {
      final decision = decisions[entry.key];
      if (decision == null ||
          !decision.matchesServerValue(entry.value.serverValue)) {
        return true;
      }
    }
    return false;
  }
}

class ConflictDetector {
  const ConflictDetector._();

  static const List<String> laboratoryFields = <String>[
    'name',
    'code',
    'description',
    'location',
    'status',
  ];

  static const List<String> assetFields = <String>[
    'code',
    'name',
    'category',
    'description',
    'location',
    'stock',
    'status',
    'condition',
    'imageUrl',
  ];

  static Map<String, Object?> normalizeLaboratoryMap(
    Map<String, Object?> raw,
  ) => <String, Object?>{
    'name': (raw['name'] as String? ?? '').trim(),
    'code': (raw['code'] as String? ?? '').trim().toUpperCase(),
    'description': (raw['description'] as String? ?? '').trim(),
    'location': (raw['location'] as String? ?? '').trim(),
    'status': (raw['status'] as String? ?? 'active').trim(),
  };

  static Map<String, Object?> normalizeAssetMap(Map<String, Object?> raw) {
    final rawStock = raw['stock'];
    final stock = switch (rawStock) {
      final int value => value,
      final num value => value.toInt(),
      final String value => int.tryParse(value.trim()) ?? 1,
      _ => 1,
    };
    return <String, Object?>{
      'code': (raw['code'] as String? ?? '').trim().toUpperCase(),
      'name': (raw['name'] as String? ?? '').trim(),
      'category': (raw['category'] as String? ?? '').trim(),
      'description': (raw['description'] as String? ?? '').trim(),
      'location': (raw['location'] as String? ?? '').trim(),
      'stock': stock,
      'status': (raw['status'] as String? ?? 'available').trim(),
      'condition': (raw['condition'] as String? ?? 'good').trim(),
      'imageUrl': (raw['imageUrl'] as String? ?? '').trim(),
    };
  }

  static ConflictAnalysis analyze({
    required Map<String, Object?> baseline,
    required Map<String, Object?> local,
    required Map<String, Object?> server,
    required Iterable<String> fields,
  }) {
    final localChanged = <String>{};
    final serverChanged = <String>{};
    final bothChanged = <String>{};
    final unchanged = <String>{};
    final disjointLocal = <String>{};
    final disjointServer = <String>{};
    final conflicts = <String, FieldConflict>{};

    for (final field in fields) {
      final baseVal = baseline[field];
      final localVal = local[field];
      final serverVal = server[field];

      final isLocalChanged = localVal != baseVal;
      final isServerChanged = serverVal != baseVal;

      if (isLocalChanged) {
        localChanged.add(field);
      }
      if (isServerChanged) {
        serverChanged.add(field);
      }

      if (!isLocalChanged && !isServerChanged) {
        unchanged.add(field);
      } else if (isLocalChanged && !isServerChanged) {
        disjointLocal.add(field);
      } else if (!isLocalChanged && isServerChanged) {
        disjointServer.add(field);
      } else {
        bothChanged.add(field);
        if (localVal != serverVal) {
          conflicts[field] = FieldConflict(
            field: field,
            baselineValue: baseVal,
            localValue: localVal,
            serverValue: serverVal,
          );
        }
      }
    }

    return ConflictAnalysis(
      localChangedFields: Set.unmodifiable(localChanged),
      serverChangedFields: Set.unmodifiable(serverChanged),
      bothChangedFields: Set.unmodifiable(bothChanged),
      unchangedFields: Set.unmodifiable(unchanged),
      disjointLocalFields: Set.unmodifiable(disjointLocal),
      disjointServerFields: Set.unmodifiable(disjointServer),
      conflicts: Map.unmodifiable(conflicts),
      baselineData: Map.unmodifiable(baseline),
      localData: Map.unmodifiable(local),
      serverData: Map.unmodifiable(server),
    );
  }
}

class ConflictDetectedException implements Exception {
  const ConflictDetectedException({
    required this.message,
    required this.analysis,
    this.serverUpdatedAt,
  });

  final String message;
  final ConflictAnalysis analysis;
  final DateTime? serverUpdatedAt;

  @override
  String toString() => message;
}
