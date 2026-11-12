import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../auth/domain/user_profile.dart';
import '../../data/activity_log_service.dart';
import '../../data/user_management_service.dart';

/// Mengelola status submit dan mendelegasikan perubahan ke service Superadmin.
class UserManagementActionCubit extends Cubit<bool> {
  UserManagementActionCubit(this._users, this._activityLog) : super(false);

  final UserManagementService _users;
  final ActivityLogService _activityLog;

  Future<UserProfile> getUser(String userId) => _users.getUser(userId);

  Future<void> createUser({
    required String fullName,
    required String email,
    required String password,
    required String role,
    required String status,
    String phoneNumber = '',
    String nim = '',
    String studyProgram = '',
    int? semester,
    String nip = '',
    String nidn = '',
  }) => _run(() async {
    await _users.createUser(
      fullName: fullName,
      email: email,
      password: password,
      role: role,
      status: status,
      phoneNumber: phoneNumber,
      nim: nim,
      studyProgram: studyProgram,
      semester: semester,
      nip: nip,
      nidn: nidn,
    );
    await _activityLog.logUserCreated(
      fullName: fullName,
      email: email,
      role: role,
    );
  });

  Future<void> updateUser({
    required String userId,
    required String fullName,
    required String role,
    required String status,
    required String originalFullName,
    required String originalRole,
    required String email,
    String phoneNumber = '',
    String nim = '',
    String studyProgram = '',
    int? semester,
    String nip = '',
    String nidn = '',
    UserProfile? originalProfile,
  }) {
    if (originalProfile != null) {
      String norm(String? value) => value?.trim() ?? '';
      final desiredNim = role == 'student' ? norm(nim) : '';
      final desiredProgram = role == 'student' ? norm(studyProgram) : '';
      final desiredSemester = role == 'student' ? semester : null;
      final desiredNip = role == 'lab_admin' ? norm(nip) : '';
      final desiredNidn = role == 'lab_admin' ? norm(nidn) : '';
      if (norm(originalProfile.fullName) == fullName.trim() &&
          originalProfile.role == role &&
          originalProfile.status == status &&
          norm(originalProfile.phoneNumber) == norm(phoneNumber) &&
          norm(originalProfile.nim) == desiredNim &&
          norm(originalProfile.studyProgram) == desiredProgram &&
          originalProfile.semester == desiredSemester &&
          norm(originalProfile.nip) == desiredNip &&
          norm(originalProfile.nidn) == desiredNidn) {
        return Future<void>.value();
      }
    }
    return _run(() async {
      final changed = await _users.updateUser(
        userId: userId,
        fullName: fullName,
        role: role,
        status: status,
        phoneNumber: phoneNumber,
        nim: nim,
        studyProgram: studyProgram,
        semester: semester,
        nip: nip,
        nidn: nidn,
      );
      if (!changed) return;
      final roleChanged = originalRole != role;
      final generalChanged =
          originalFullName.trim() != fullName.trim() || !roleChanged;
      if (generalChanged) {
        await _activityLog.logUserUpdated(fullName: fullName, email: email);
      }
      if (roleChanged) {
        await _activityLog.logUserRoleChanged(
          fullName: fullName,
          email: email,
          oldRole: originalRole,
          newRole: role,
        );
      }
    });
  }

  Future<void> setUserStatus({
    required String userId,
    required String fullName,
    required String email,
    required bool suspend,
  }) => _run(() async {
    if (suspend) {
      final changed = await _users.suspendUser(userId);
      if (changed) {
        await _activityLog.logUserSuspended(fullName: fullName, email: email);
      }
    } else {
      final changed = await _users.activateUser(userId);
      if (changed) {
        await _activityLog.logUserActivated(fullName: fullName, email: email);
      }
    }
  });

  Future<void> requestEmailChange({
    required String userId,
    required String newEmail,
  }) =>
      _run(() => _users.requestEmailChange(userId: userId, newEmail: newEmail));

  Future<void> sendPasswordReset({required String userId}) =>
      _run(() => _users.sendPasswordReset(userId));

  Future<void> _run(Future<void> Function() operation) async {
    if (state) return;
    emit(true);
    try {
      await operation();
    } finally {
      emit(false);
    }
  }
}
