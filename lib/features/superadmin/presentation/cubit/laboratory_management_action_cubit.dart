import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/offline/conflict_resolution.dart';
import '../../../laboratory/data/laboratory_service.dart';
import '../../../laboratory/domain/laboratory.dart';
import '../../data/activity_log_service.dart';

/// Mengelola status operasi dan audit untuk perubahan laboratorium.
class LaboratoryManagementActionCubit extends Cubit<bool> {
  LaboratoryManagementActionCubit(this._laboratories, this._activityLog)
    : super(false);

  final LaboratoryService _laboratories;
  final ActivityLogService _activityLog;

  Future<Laboratory> getLaboratory(String id) =>
      _laboratories.getLaboratory(id);

  Future<void> createLaboratory({
    required String name,
    required String code,
    required String description,
    required String location,
    required String status,
  }) => _run(() async {
    await _laboratories.createLaboratory(
      name: name,
      code: code,
      description: description,
      location: location,
      status: status,
    );
    await _activityLog.createActivity(
      type: 'laboratory',
      title: 'Laboratorium dibuat',
      description:
          '$code — $name berhasil dibuat dengan status ${_statusLabel(status)}.',
      reference: code,
    );
  });

  Future<Map<String, Object?>> updateLaboratory({
    required String laboratoryId,
    required String name,
    required String code,
    required String description,
    required String location,
    required String status,
    required Laboratory original,
    Map<String, Object?>? baselineData,
    Map<String, ConflictResolutionDecision>? conflictDecisions,
  }) async {
    final cleanName = name.trim();
    final cleanCode = code.trim().toUpperCase();
    final cleanDescription = description.trim();
    final cleanLocation = location.trim();
    if (conflictDecisions == null &&
        original.name.trim() == cleanName &&
        original.code.trim().toUpperCase() == cleanCode &&
        original.description.trim() == cleanDescription &&
        original.location.trim() == cleanLocation &&
        original.status == status) {
      return const <String, Object?>{};
    }

    var appliedUpdate = const <String, Object?>{};
    await _run(() async {
      appliedUpdate = await _laboratories.updateLaboratory(
        laboratoryId: laboratoryId,
        name: name,
        code: code,
        description: description,
        location: location,
        status: status,
        baselineData: baselineData,
        conflictDecisions: conflictDecisions,
      );

      if (appliedUpdate.isEmpty) {
        return;
      }

      final generalDataChanged =
          appliedUpdate.containsKey('name') ||
          appliedUpdate.containsKey('code') ||
          appliedUpdate.containsKey('location') ||
          appliedUpdate.containsKey('description');
      final effectiveCode =
          (appliedUpdate['code'] as String?) ??
          code.trim().toUpperCase();
      final effectiveName =
          (appliedUpdate['name'] as String?) ?? name.trim();

      if (generalDataChanged) {
        await _activityLog.createActivity(
          type: 'laboratory',
          title: 'Laboratorium diperbarui',
          description: '$effectiveCode — $effectiveName berhasil diperbarui.',
          reference: effectiveCode,
        );
      }

      if (appliedUpdate.containsKey('status')) {
        final effectiveStatus =
            (appliedUpdate['status'] as String?) ?? status;
        final title = switch ((original.status, effectiveStatus)) {
          ('active', 'inactive') => 'Laboratorium dinonaktifkan',
          ('inactive', 'active') => 'Laboratorium diaktifkan kembali',
          _ => 'Status laboratorium diubah',
        };
        final description = switch ((original.status, effectiveStatus)) {
          ('active', 'inactive') =>
            '$effectiveCode — $effectiveName dinonaktifkan.',
          ('inactive', 'active') =>
            '$effectiveCode — $effectiveName diaktifkan kembali.',
          _ =>
            'Status $effectiveCode — $effectiveName diubah dari ${_statusLabel(original.status)} menjadi ${_statusLabel(effectiveStatus)}.',
        };
        await _activityLog.createActivity(
          type: 'laboratory',
          title: title,
          description: description,
          reference: effectiveCode,
        );
      }
    });
    return appliedUpdate;
  }

  Future<void> deleteLaboratory({
    required String laboratoryId,
    required String name,
    required String code,
  }) => _run(() async {
    await _laboratories.deleteLaboratory(laboratoryId);
    await _activityLog.createActivity(
      type: 'laboratory',
      title: 'Laboratorium dihapus',
      description: '$code — $name dihapus dari sistem.',
      reference: code,
    );
  });

  Future<void> _run(Future<void> Function() operation) async {
    if (state) return;
    emit(true);
    try {
      await operation();
    } finally {
      emit(false);
    }
  }

  String _statusLabel(String status) => switch (status) {
    'active' => 'Aktif',
    'inactive' => 'Tidak Aktif',
    _ => status,
  };
}
