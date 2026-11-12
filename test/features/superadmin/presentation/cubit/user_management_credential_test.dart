import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:labflow/features/superadmin/data/activity_log_service.dart';
import 'package:labflow/features/superadmin/data/admin_credential_service.dart';
import 'package:labflow/features/superadmin/data/user_management_service.dart';
import 'package:labflow/features/superadmin/presentation/cubit/user_management_action_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _UserServiceMock extends Mock implements UserManagementService {}

class _ActivityLogMock extends Mock implements ActivityLogService {}

class _FirebaseAuthMock extends Mock implements FirebaseAuth {}

class _UserMock extends Mock implements User {}

class _HttpClientMock extends Mock implements http.Client {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uri.parse('http://127.0.0.1'));
  });

  late _UserServiceMock users;
  late _ActivityLogMock logs;
  late UserManagementActionCubit cubit;

  setUp(() {
    users = _UserServiceMock();
    logs = _ActivityLogMock();
    cubit = UserManagementActionCubit(users, logs);
  });

  tearDown(() async => cubit.close());

  test('delegates email change to the trusted credential service', () async {
    when(
      () => users.requestEmailChange(
        userId: 'target-1',
        newEmail: 'new@example.com',
      ),
    ).thenAnswer((_) async {});

    await cubit.requestEmailChange(
      userId: 'target-1',
      newEmail: 'new@example.com',
    );

    verify(
      () => users.requestEmailChange(
        userId: 'target-1',
        newEmail: 'new@example.com',
      ),
    ).called(1);
    expect(cubit.state, isFalse);
  });

  test('delegates password reset to the target account', () async {
    when(() => users.sendPasswordReset('target-1')).thenAnswer((_) async {});

    await cubit.sendPasswordReset(userId: 'target-1');

    verify(() => users.sendPasswordReset('target-1')).called(1);
    expect(cubit.state, isFalse);
  });

  test('does not start a second credential action while busy', () async {
    final completer = Future<void>.delayed(const Duration(milliseconds: 20));
    when(() => users.sendPasswordReset('target-1'))
        .thenAnswer((_) => completer);

    final first = cubit.sendPasswordReset(userId: 'target-1');
    await Future<void>.delayed(Duration.zero);
    await cubit.sendPasswordReset(userId: 'target-2');
    await first;

    verify(() => users.sendPasswordReset('target-1')).called(1);
    verifyNever(() => users.sendPasswordReset('target-2'));
  });

  group('AdminCredentialService Endpoint Resolution', () {
    test('resolves production endpoint by default', () {
      final url = AdminCredentialService.resolveBaseUrl();
      expect(
        url,
        'https://us-central1-labflow-academic-2026.cloudfunctions.net',
      );
    });

    test('resolves emulator endpoint with explicit parameters', () {
      final url = AdminCredentialService.resolveBaseUrl(
        env: 'emulator',
        emulatorHost: '10.0.2.2',
        emulatorPort: 18081,
        projectId: 'labflow-academic-2026',
        region: 'us-central1',
      );
      expect(
        url,
        'http://10.0.2.2:18081/labflow-academic-2026/us-central1',
      );
    });

    test('resolves custom base url overriding any env', () {
      final url = AdminCredentialService.resolveBaseUrl(
        env: 'emulator',
        customBaseUrl: 'http://127.0.0.1:18081/custom-project/us-central1/',
      );
      expect(
        url,
        'http://127.0.0.1:18081/custom-project/us-central1',
      );
    });

    test('fails closed when environment configuration is unrecognized', () {
      expect(
        () => AdminCredentialService.resolveBaseUrl(env: 'unknown_environment'),
        throwsA(
          isA<AdminCredentialException>().having(
            (e) => e.code,
            'code',
            'invalid-env-config',
          ),
        ),
      );
    });

    test('fails closed with AdminCredentialException when emulator configuration is invalid', () {
      expect(
        () => AdminCredentialService.resolveBaseUrl(
          env: 'emulator',
          emulatorHost: '',
          emulatorPort: 18081,
        ),
        throwsA(
          isA<AdminCredentialException>().having(
            (e) => e.code,
            'code',
            'invalid-emulator-config',
          ),
        ),
      );

      expect(
        () => AdminCredentialService.resolveBaseUrl(
          env: 'emulator',
          emulatorHost: '10.0.2.2',
          emulatorPort: -1,
        ),
        throwsA(isA<AdminCredentialException>()),
      );
    });
  });

  group('AdminCredentialService HTTP Calls and Safe Message Handling', () {
    late _FirebaseAuthMock mockAuth;
    late _UserMock mockUser;
    late _HttpClientMock mockHttp;
    late AdminCredentialService credentialService;

    setUp(() {
      mockAuth = _FirebaseAuthMock();
      mockUser = _UserMock();
      mockHttp = _HttpClientMock();

      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(() => mockUser.getIdToken()).thenAnswer((_) async => 'fake-superadmin-token');

      credentialService = AdminCredentialService(
        firebaseAuth: mockAuth,
        client: mockHttp,
        baseUrl: 'http://10.0.2.2:18081/labflow-academic-2026/us-central1',
      );
    });

    test('sends POST with bearer token and body to Cloud Function', () async {
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({'result': {'status': 'reset_sent'}}),
          200,
        ),
      );

      await credentialService.sendPasswordReset(targetUid: 'target-123');

      verify(
        () => mockHttp.post(
          Uri.parse('http://10.0.2.2:18081/labflow-academic-2026/us-central1/adminSendPasswordReset'),
          headers: {
            'Authorization': 'Bearer fake-superadmin-token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'data': {'targetUid': 'target-123'},
          }),
        ),
      ).called(1);
    });

    test('preserves allowed backend error messages', () async {
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'error': {
              'message': 'Email baru sama dengan email saat ini.',
              'status': 'ALREADY_EXISTS',
            },
          }),
          409,
        ),
      );

      expect(
        () => credentialService.requestEmailChange(
          targetUid: 'target-123',
          newEmail: 'same@example.com',
        ),
        throwsA(
          isA<AdminCredentialException>().having(
            (e) => e.message,
            'message',
            'Email baru sama dengan email saat ini.',
          ),
        ),
      );
    });

    test('maps unknown backend errors to generic safe message', () async {
      when(
        () => mockHttp.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          'Internal Database Exploded at row 42',
          500,
        ),
      );

      expect(
        () => credentialService.sendPasswordReset(targetUid: 'target-123'),
        throwsA(
          isA<AdminCredentialException>().having(
            (e) => e.message,
            'message',
            'Permintaan kredensial tidak dapat diproses.',
          ),
        ),
      );
    });
  });
}
