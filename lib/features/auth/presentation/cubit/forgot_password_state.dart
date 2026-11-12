sealed class ForgotPasswordState {
  const ForgotPasswordState();
}

final class ForgotPasswordInitial extends ForgotPasswordState {
  const ForgotPasswordInitial();
}

final class ForgotPasswordLoading extends ForgotPasswordState {
  const ForgotPasswordLoading();
}

final class ForgotPasswordSuccess extends ForgotPasswordState {
  const ForgotPasswordSuccess();
}

final class ForgotPasswordFailure extends ForgotPasswordState {
  const ForgotPasswordFailure(this.message, {this.code = 'unknown'});

  final String message;
  final String code;
}
