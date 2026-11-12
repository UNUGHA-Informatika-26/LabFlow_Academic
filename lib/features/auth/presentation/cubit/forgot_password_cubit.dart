import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/validators/auth_validator.dart';
import '../../data/auth_service.dart';
import 'forgot_password_state.dart';

class ForgotPasswordCubit extends Cubit<ForgotPasswordState> {
  ForgotPasswordCubit(this._authService) : super(const ForgotPasswordInitial());

  final AuthService _authService;

  Future<void> submit(String email) async {
    if (state is ForgotPasswordLoading) return;

    final validationError = AuthValidator.validateEmail(email);
    if (validationError != null) {
      emit(ForgotPasswordFailure(validationError, code: 'validation'));
      return;
    }

    emit(const ForgotPasswordLoading());
    try {
      await _authService.sendPasswordResetEmail(email: email);
      emit(const ForgotPasswordSuccess());
    } on AuthServiceException catch (error) {
      // Jangan mengungkapkan apakah alamat email terdaftar.
      if (error.code == 'user-not-found') {
        emit(const ForgotPasswordSuccess());
        return;
      }
      emit(ForgotPasswordFailure(error.message, code: error.code));
    } catch (_) {
      emit(
        const ForgotPasswordFailure(
          'Tautan reset password belum dapat dikirim. Silakan coba lagi.',
        ),
      );
    }
  }
}
