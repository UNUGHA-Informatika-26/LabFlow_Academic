import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:labflow/features/auth/data/auth_service.dart';
import 'package:labflow/features/auth/presentation/cubit/change_password_cubit.dart';
import 'package:labflow/features/auth/presentation/cubit/change_password_state.dart';
import 'package:labflow/features/auth/presentation/cubit/forgot_password_cubit.dart';
import 'package:labflow/features/auth/presentation/cubit/forgot_password_state.dart';
import 'package:mocktail/mocktail.dart';

class _AuthServiceMock extends Mock implements AuthService {}

void main() {
  group('ChangePasswordCubit', () {
    late _AuthServiceMock auth;

    setUp(() => auth = _AuthServiceMock());

    blocTest<ChangePasswordCubit, ChangePasswordState>(
      'rejects empty current password without calling Firebase service',
      build: () => ChangePasswordCubit(auth),
      act: (cubit) => cubit.submit(
        currentPassword: '',
        newPassword: 'Newpass1!',
        confirmation: 'Newpass1!',
      ),
      expect: () => [
        isA<ChangePasswordFailure>().having(
          (state) => state.message,
          'message',
          'Password saat ini wajib diisi.',
        ),
      ],
      verify: (_) => verifyNever(
        () => auth.changePassword(
          currentPassword: any(named: 'currentPassword'),
          newPassword: any(named: 'newPassword'),
        ),
      ),
    );

    blocTest<ChangePasswordCubit, ChangePasswordState>(
      'rejects weak password and mismatched confirmation',
      build: () => ChangePasswordCubit(auth),
      act: (cubit) async {
        await cubit.submit(
          currentPassword: 'Oldpass1!',
          newPassword: 'short',
          confirmation: 'short',
        );
        await cubit.submit(
          currentPassword: 'Oldpass1!',
          newPassword: 'Newpass1!',
          confirmation: 'Different1!',
        );
      },
      expect: () => [
        isA<ChangePasswordFailure>().having(
          (state) => state.message,
          'message',
          'Password minimal 8 karakter.',
        ),
        isA<ChangePasswordFailure>().having(
          (state) => state.message,
          'message',
          'Konfirmasi password tidak sama.',
        ),
      ],
    );

    blocTest<ChangePasswordCubit, ChangePasswordState>(
      'delegates valid change and emits success',
      build: () {
        when(
          () => auth.changePassword(
            currentPassword: any(named: 'currentPassword'),
            newPassword: any(named: 'newPassword'),
          ),
        ).thenAnswer((_) async {});
        return ChangePasswordCubit(auth);
      },
      act: (cubit) => cubit.submit(
        currentPassword: 'Oldpass1!',
        newPassword: 'Newpass1!',
        confirmation: 'Newpass1!',
      ),
      expect: () => [
        isA<ChangePasswordLoading>(),
        isA<ChangePasswordSuccess>(),
      ],
      verify: (_) => verify(
        () => auth.changePassword(
          currentPassword: 'Oldpass1!',
          newPassword: 'Newpass1!',
        ),
      ).called(1),
    );

    blocTest<ChangePasswordCubit, ChangePasswordState>(
      'surfaces re-authentication failure without exposing password',
      build: () {
        when(
          () => auth.changePassword(
            currentPassword: any(named: 'currentPassword'),
            newPassword: any(named: 'newPassword'),
          ),
        ).thenThrow(
          const AuthServiceException(
            'Password saat ini tidak sesuai.',
            code: 'wrong-password',
          ),
        );
        return ChangePasswordCubit(auth);
      },
      act: (cubit) => cubit.submit(
        currentPassword: 'Oldpass1!',
        newPassword: 'Newpass1!',
        confirmation: 'Newpass1!',
      ),
      expect: () => [
        isA<ChangePasswordLoading>(),
        isA<ChangePasswordFailure>().having(
          (state) => state.message,
          'message',
          'Password saat ini tidak sesuai.',
        ),
      ],
    );
  });

  group('ForgotPasswordCubit', () {
    late _AuthServiceMock auth;

    setUp(() => auth = _AuthServiceMock());

    blocTest<ForgotPasswordCubit, ForgotPasswordState>(
      'rejects empty and malformed email',
      build: () => ForgotPasswordCubit(auth),
      act: (cubit) async {
        await cubit.submit('');
        await cubit.submit('not-an-email');
      },
      expect: () => [
        isA<ForgotPasswordFailure>(),
        isA<ForgotPasswordFailure>(),
      ],
      verify: (_) => verifyNever(
        () => auth.sendPasswordResetEmail(email: any(named: 'email')),
      ),
    );

    blocTest<ForgotPasswordCubit, ForgotPasswordState>(
      'sends valid reset request and emits success',
      build: () {
        when(() => auth.sendPasswordResetEmail(email: any(named: 'email')))
            .thenAnswer((_) async {});
        return ForgotPasswordCubit(auth);
      },
      act: (cubit) => cubit.submit('student@example.com'),
      expect: () => [
        isA<ForgotPasswordLoading>(),
        isA<ForgotPasswordSuccess>(),
      ],
      verify: (_) => verify(
        () => auth.sendPasswordResetEmail(email: 'student@example.com'),
      ).called(1),
    );

    blocTest<ForgotPasswordCubit, ForgotPasswordState>(
      'keeps account existence generic for user-not-found',
      build: () {
        when(
          () => auth.sendPasswordResetEmail(email: any(named: 'email')),
        ).thenThrow(
          const AuthServiceException('reset failed', code: 'user-not-found'),
        );
        return ForgotPasswordCubit(auth);
      },
      act: (cubit) => cubit.submit('student@example.com'),
      expect: () => [
        isA<ForgotPasswordLoading>(),
        isA<ForgotPasswordSuccess>(),
      ],
    );

    blocTest<ForgotPasswordCubit, ForgotPasswordState>(
      'surfaces network failure without account enumeration',
      build: () {
        when(() => auth.sendPasswordResetEmail(email: any(named: 'email')))
            .thenThrow(
              const AuthServiceException(
                'Tidak dapat terhubung ke internet.',
                code: 'network-request-failed',
              ),
            );
        return ForgotPasswordCubit(auth);
      },
      act: (cubit) => cubit.submit('student@example.com'),
      expect: () => [
        isA<ForgotPasswordLoading>(),
        isA<ForgotPasswordFailure>().having(
          (state) => state.message,
          'message',
          'Tidak dapat terhubung ke internet.',
        ),
      ],
    );
  });
}
