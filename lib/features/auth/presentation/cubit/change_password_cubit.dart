import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/validators/auth_validator.dart';
import '../../data/auth_service.dart';
import 'change_password_state.dart';

class ChangePasswordCubit extends Cubit<ChangePasswordState> {
  ChangePasswordCubit(this._authService) : super(const ChangePasswordInitial());

  final AuthService _authService;

  Future<void> submit({
    required String currentPassword,
    required String newPassword,
    required String confirmation,
  }) async {
    if (state is ChangePasswordLoading) return;

    if (currentPassword.isEmpty) {
      emit(
        const ChangePasswordFailure(
          'Password saat ini wajib diisi.',
          code: 'validation',
        ),
      );
      return;
    }

    final validationError = AuthValidator.validatePassword(newPassword);
    if (validationError != null) {
      emit(ChangePasswordFailure(validationError, code: 'validation'));
      return;
    }

    if (confirmation.isEmpty) {
      emit(
        const ChangePasswordFailure(
          'Konfirmasi password wajib diisi.',
          code: 'validation',
        ),
      );
      return;
    }

    if (newPassword != confirmation) {
      emit(
        const ChangePasswordFailure(
          'Konfirmasi password tidak sama.',
          code: 'validation',
        ),
      );
      return;
    }

    if (currentPassword == newPassword) {
      emit(
        const ChangePasswordFailure(
          'Password baru harus berbeda dari password saat ini.',
          code: 'validation',
        ),
      );
      return;
    }

    emit(const ChangePasswordLoading());
    try {
      await _authService.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      emit(const ChangePasswordSuccess());
    } on AuthServiceException catch (error) {
      emit(ChangePasswordFailure(error.message, code: error.code));
    } catch (_) {
      emit(
        const ChangePasswordFailure(
          'Password tidak dapat diubah. Silakan coba kembali.',
        ),
      );
    }
  }
}
