import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:labflow/features/auth/domain/user_profile.dart';
import 'package:labflow/features/superadmin/data/activity_log_service.dart';
import 'package:labflow/features/superadmin/data/user_management_service.dart';
import 'package:labflow/features/superadmin/presentation/cubit/user_detail_cubit.dart';
import 'package:labflow/features/superadmin/presentation/cubit/user_management_action_cubit.dart';
import 'package:labflow/features/superadmin/presentation/pages/edit_user_page.dart';
import 'package:mocktail/mocktail.dart';

class _UserManagementServiceMock extends Mock implements UserManagementService {}

class _ActivityLogMock extends Mock implements ActivityLogService {}

void main() {
  late _UserManagementServiceMock mockUsers;
  late _ActivityLogMock mockLogs;
  late UserManagementActionCubit actionCubit;
  late UserDetailCubit detailCubit;

  const targetProfile = UserProfile(
    uid: 'target-student-1',
    email: 'student@example.test',
    fullName: 'Mahasiswa Uji',
    role: 'student',
    status: 'active',
    nim: '12345678',
    studyProgram: 'Informatika',
    semester: 5,
  );

  const targetProfileWithPending = UserProfile(
    uid: 'target-student-1',
    email: 'student@example.test',
    fullName: 'Mahasiswa Uji',
    role: 'student',
    status: 'active',
    nim: '12345678',
    studyProgram: 'Informatika',
    semester: 5,
    pendingEmail: 'student-new@example.test',
    emailChangeStatus: 'sent',
  );

  setUp(() {
    mockUsers = _UserManagementServiceMock();
    mockLogs = _ActivityLogMock();
    actionCubit = UserManagementActionCubit(mockUsers, mockLogs);
    detailCubit = UserDetailCubit(mockUsers);
  });

  tearDown(() async {
    await actionCubit.close();
    await detailCubit.close();
  });

  Widget buildWidget({required UserProfile profile}) {
    when(() => mockUsers.getUser(profile.uid)).thenAnswer((_) async => profile);

    return MaterialApp(
      home: EditUserPage(
        userId: profile.uid,
        actionCubit: actionCubit,
        detailCubit: detailCubit..load(profile.uid),
      ),
    );
  }

  group('EditUserPage Credential Management Widget Tests', () {
    testWidgets('renders read-only managed email and password reset instruction dialog', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildWidget(profile: targetProfile));
      await tester.pumpAndSettle();

      expect(find.text('Edit Pengguna'), findsOneWidget);
      expect(find.text('Petunjuk Reset Password'), findsOneWidget);

      final resetBtn = find.text('Petunjuk Reset Password');
      await tester.ensureVisible(resetBtn);
      await tester.tap(resetBtn);
      await tester.pumpAndSettle();

      expect(find.text('Prosedur Reset Password'), findsOneWidget);
      expect(
        find.textContaining('Firebase Authentication Console -> Tab Users -> Kirim Email Reset Password'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Mengerti'));
      await tester.pumpAndSettle();
      expect(find.text('Prosedur Reset Password'), findsNothing);
    });

    testWidgets('shows pending email badge when profile has pending email change', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildWidget(profile: targetProfileWithPending));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Perubahan email tertunda: student-new@example.test'),
        findsOneWidget,
      );
    });
  });
}
