sealed class ChangePasswordState {
  const ChangePasswordState();
}

final class ChangePasswordInitial extends ChangePasswordState {
  const ChangePasswordInitial();
}

final class ChangePasswordLoading extends ChangePasswordState {
  const ChangePasswordLoading();
}

final class ChangePasswordSuccess extends ChangePasswordState {
  const ChangePasswordSuccess();
}

final class ChangePasswordFailure extends ChangePasswordState {
  const ChangePasswordFailure(this.message, {this.code = 'unknown'});

  final String message;
  final String code;
}
