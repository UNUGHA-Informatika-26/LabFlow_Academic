import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/presentation/navigation/labflow_back_fallback.dart';

import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/account_security_page.dart';
import '../../features/auth/presentation/pages/request_email_change_page.dart';
import '../../features/auth/presentation/pages/superadmin_email_requests_page.dart';
import '../../features/auth/presentation/pages/forgot_password_page.dart';
import '../../features/auth/presentation/widgets/labflow_account_status_gate.dart';
import '../../features/borrowing/presentation/pages/admin_borrow_request_detail_page.dart';
import '../../features/borrowing/presentation/pages/admin_borrow_requests_page.dart';
import '../../features/borrowing/presentation/pages/asset_assignment_page.dart';
import '../../features/borrowing/presentation/pages/pickup_verification_page.dart';
import '../../features/borrowing/presentation/pages/return_condition_page.dart';
import '../../features/borrowing/presentation/pages/return_verification_page.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';
import '../../features/lab_admin/presentation/pages/asset_detail_page.dart';
import '../../features/lab_admin/presentation/pages/asset_management_page.dart';
import '../../features/lab_admin/presentation/pages/create_asset_page.dart';
import '../../features/lab_admin/presentation/pages/edit_asset_page.dart';
import '../../features/lab_admin/presentation/pages/lab_admin_dashboard_page.dart';
import '../../features/lab_admin/presentation/pages/lab_admin_profile_page.dart';
import '../../features/maintenance/presentation/pages/create_maintenance_page.dart';
import '../../features/maintenance/presentation/pages/maintenance_detail_page.dart';
import '../../features/maintenance/presentation/pages/maintenance_list_page.dart';
import '../../features/onboarding/presentation/pages/onboarding_page.dart';
import '../../features/profile/presentation/pages/profile_edit_page.dart';
import '../../features/profile/presentation/pages/application_guide_page.dart';
import '../../features/profile/presentation/pages/about_labflow_page.dart';
import '../../features/profile/presentation/pages/labflow_settings_page.dart';
import '../../features/reporting/presentation/pages/admin_report_detail_page.dart';
import '../../features/reporting/presentation/pages/admin_report_list_page.dart';
import '../../features/splash/presentation/pages/splash_page.dart';
import '../../features/student/presentation/pages/student_home_page.dart';
import '../../features/student/presentation/pages/student_asset_detail_page.dart';
import '../../features/student/presentation/pages/student_borrowing_page.dart';
import '../../features/student/presentation/pages/student_borrowing_detail_page.dart';
import '../../features/student/presentation/pages/student_borrow_request_page.dart';
import '../../features/student/presentation/pages/student_equipment_page.dart';
import '../../features/student/presentation/pages/student_profile_page.dart';
import '../../features/student/presentation/pages/student_qr_scanner_page.dart';
import '../../features/student/presentation/pages/student_reports_page.dart';
import '../../features/student/presentation/pages/student_report_detail_page.dart';
import '../../features/student/presentation/pages/student_report_create_page.dart';
import '../../features/notifications/presentation/pages/notification_center_page.dart';
import '../../features/student/presentation/student_navigation.dart';
import '../../features/superadmin/presentation/pages/activity_log_page.dart';
import '../../features/superadmin/presentation/pages/create_laboratory_page.dart';
import '../../features/superadmin/presentation/pages/create_user_page.dart';
import '../../features/superadmin/presentation/pages/edit_laboratory_page.dart';
import '../../features/superadmin/presentation/pages/edit_user_page.dart';
import '../../features/superadmin/presentation/pages/lab_membership_page.dart';
import '../../features/superadmin/presentation/pages/laboratory_management_page.dart';
import '../../features/superadmin/presentation/pages/superadmin_dashboard_page.dart';
import '../../features/superadmin/presentation/pages/superadmin_profile_page.dart';
import '../../features/superadmin/presentation/pages/user_management_page.dart';

/// Membuat router utama LabFlow.
///
/// Protected route menggunakan LabFlowAccountStatusGate
/// untuk memverifikasi session, status akun, dan role.
GoRouter createAppRouter({required String initialLocation}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashPage()),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingPage(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordPage(),
      ),

      /// Dashboard placeholder lama.
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const DashboardPage(),
      ),

      /// Area Superadmin.
      GoRoute(
        path: '/superadmin',
        builder: (context, state) {
          return const LabFlowAccountStatusGate(
            requiredRole: 'superadmin',
            child: SuperadminDashboardPage(),
          );
        },
      ),
      GoRoute(
        path: '/superadmin/users',
        builder: (context, state) {
          return const LabFlowAccountStatusGate(
            requiredRole: 'superadmin',
            child: UserManagementPage(),
          );
        },
      ),
      GoRoute(
        path: '/superadmin/users/create',
        builder: (context, state) {
          return const LabFlowAccountStatusGate(
            requiredRole: 'superadmin',
            child: CreateUserPage(),
          );
        },
      ),
      GoRoute(
        path: '/superadmin/labs',
        builder: (context, state) {
          return const LabFlowAccountStatusGate(
            requiredRole: 'superadmin',
            child: LaboratoryManagementPage(),
          );
        },
      ),
      GoRoute(
        path: '/superadmin/labs/create',
        builder: (context, state) {
          return const LabFlowAccountStatusGate(
            requiredRole: 'superadmin',
            child: CreateLaboratoryPage(),
          );
        },
      ),
      GoRoute(
        path: '/superadmin/memberships',
        builder: (context, state) {
          return const LabFlowAccountStatusGate(
            requiredRole: 'superadmin',
            child: LabMembershipPage(),
          );
        },
      ),
      GoRoute(
        path: '/superadmin/labs/:labId/edit',
        builder: (context, state) {
          final labId = state.pathParameters['labId']!;

          return LabFlowAccountStatusGate(
            requiredRole: 'superadmin',
            child: EditLaboratoryPage(laboratoryId: labId),
          );
        },
      ),
      GoRoute(
        path: '/superadmin/users/:userId/edit',
        builder: (context, state) {
          final userId = state.pathParameters['userId']!;

          return LabFlowAccountStatusGate(
            requiredRole: 'superadmin',
            child: EditUserPage(userId: userId),
          );
        },
      ),
      GoRoute(
        path: '/superadmin/activity',
        builder: (context, state) {
          return const LabFlowAccountStatusGate(
            requiredRole: 'superadmin',
            child: ActivityLogPage(),
          );
        },
      ),
      GoRoute(
        path: '/superadmin/notifications',
        builder: (context, state) => const LabFlowAccountStatusGate(
          requiredRole: 'superadmin',
          child: NotificationCenterPage(role: 'superadmin'),
        ),
      ),
      GoRoute(
        path: '/superadmin/profile',
        builder: (context, state) {
          return const LabFlowAccountStatusGate(
            requiredRole: 'superadmin',
            child: SuperadminProfilePage(),
          );
        },
      ),
      GoRoute(
        path: '/superadmin/profile/edit',
        builder: (context, state) => const LabFlowAccountStatusGate(
          requiredRole: 'superadmin',
          child: ProfileEditPage(returnPath: '/superadmin/profile'),
        ),
      ),
      GoRoute(
        path: '/superadmin/profile/guide',
        builder: (context, state) => const LabFlowAccountStatusGate(
          requiredRole: 'superadmin',
          child: ApplicationGuidePage(
            role: 'superadmin',
            returnPath: '/superadmin/profile',
          ),
        ),
      ),
      GoRoute(
        path: '/superadmin/profile/settings',
        builder: (context, state) => const LabFlowAccountStatusGate(
          requiredRole: 'superadmin',
          child: LabFlowSettingsPage(
            role: 'superadmin',
            returnPath: '/superadmin/profile',
          ),
        ),
      ),
      GoRoute(
        path: '/superadmin/profile/security',
        builder: (context, state) => const LabFlowAccountStatusGate(
          requiredRole: 'superadmin',
          child: AccountSecurityPage(returnPath: '/superadmin/profile'),
        ),
      ),
      GoRoute(
        path: '/superadmin/email-requests',
        builder: (context, state) => const LabFlowAccountStatusGate(
          requiredRole: 'superadmin',
          child: SuperadminEmailRequestsPage(),
        ),
      ),
      GoRoute(
        path: '/superadmin/profile/security/change-email',
        builder: (context, state) => const LabFlowAccountStatusGate(
          requiredRole: 'superadmin',
          child: RequestEmailChangePage(),
        ),
      ),
      GoRoute(
        path: '/superadmin/profile/security/change-password',
        builder: (context, state) => const LabFlowAccountStatusGate(
          requiredRole: 'superadmin',
          child: ChangePasswordPage(),
        ),
      ),
      GoRoute(
        path: '/superadmin/profile/about',
        builder: (context, state) => const LabFlowAccountStatusGate(
          requiredRole: 'superadmin',
          child: AboutLabFlowPage(returnPath: '/superadmin/profile'),
        ),
      ),

      /// Area Student.
      GoRoute(
        path: '/student',
        builder: (context, state) {
          return const LabFlowAccountStatusGate(
            requiredRole: 'student',
            child: StudentHomePage(),
          );
        },
      ),
      GoRoute(
        path: '/student/assets',
        builder: (context, state) {
          return const LabFlowAccountStatusGate(
            requiredRole: 'student',
            child: StudentEquipmentPage(),
          );
        },
      ),
      GoRoute(
        path: '/student/scanner',
        builder: (context, state) => const LabFlowAccountStatusGate(
          requiredRole: 'student',
          child: StudentQrScannerPage(),
        ),
      ),
      GoRoute(
        path: '/student/assets/:assetId',
        builder: (context, state) {
          final assetId = state.pathParameters['assetId']!;

          return LabFlowAccountStatusGate(
            requiredRole: 'student',
            child: LabFlowBackFallback(
              fallbackPath: '/student/assets',
              child: StudentAssetDetailPage(assetId: assetId),
            ),
          );
        },
      ),
      GoRoute(
        path: '/student/borrowing',
        builder: (context, state) {
          return const LabFlowAccountStatusGate(
            requiredRole: 'student',
            child: StudentBorrowingPage(),
          );
        },
      ),
      GoRoute(
        path: studentBorrowRequestFormPath,
        builder: (context, state) {
          final assetId = state.uri.queryParameters['assetId']?.trim() ?? '';

          if (assetId.isEmpty) {
            return const Scaffold(
              body: Center(child: Text('Aset peminjaman tidak valid.')),
            );
          }

          return LabFlowAccountStatusGate(
            requiredRole: 'student',
            child: LabFlowBackFallback(
              fallbackPath: '/student/assets/${Uri.encodeComponent(assetId)}',
              child: StudentBorrowRequestPage(assetId: assetId),
            ),
          );
        },
      ),
      GoRoute(
        path: '/student/borrowing/:requestId',
        builder: (context, state) {
          final requestId = state.pathParameters['requestId']!;

          return LabFlowAccountStatusGate(
            requiredRole: 'student',
            child: LabFlowBackFallback(
              fallbackPath: '/student/borrowing',
              child: StudentBorrowingDetailPage(requestId: requestId),
            ),
          );
        },
      ),
      GoRoute(
        path: '/student/reports',
        builder: (context, state) {
          return const LabFlowAccountStatusGate(
            requiredRole: 'student',
            child: StudentReportsPage(),
          );
        },
      ),
      GoRoute(
        path: '/student/reports/create',
        builder: (context, state) => const LabFlowAccountStatusGate(
          requiredRole: 'student',
          child: LabFlowBackFallback(
            fallbackPath: '/student/reports',
            child: StudentReportCreatePage(),
          ),
        ),
      ),
      GoRoute(
        path: '/student/reports/:reportId',
        builder: (context, state) {
          final reportId = state.pathParameters['reportId']!;

          return LabFlowAccountStatusGate(
            requiredRole: 'student',
            child: StudentReportDetailPage(reportId: reportId),
          );
        },
      ),
      GoRoute(
        path: '/student/profile',
        builder: (context, state) {
          return const LabFlowAccountStatusGate(
            requiredRole: 'student',
            child: StudentProfilePage(),
          );
        },
      ),
      GoRoute(
        path: '/student/profile/edit',
        builder: (context, state) => const LabFlowAccountStatusGate(
          requiredRole: 'student',
          child: ProfileEditPage(returnPath: '/student/profile'),
        ),
      ),
      GoRoute(
        path: '/student/profile/guide',
        builder: (context, state) => const LabFlowAccountStatusGate(
          requiredRole: 'student',
          child: ApplicationGuidePage(
            role: 'student',
            returnPath: '/student/profile',
          ),
        ),
      ),
      GoRoute(
        path: '/student/profile/settings',
        builder: (context, state) => const LabFlowAccountStatusGate(
          requiredRole: 'student',
          child: LabFlowSettingsPage(
            role: 'student',
            returnPath: '/student/profile',
          ),
        ),
      ),
      GoRoute(
        path: '/student/profile/security',
        builder: (context, state) => const LabFlowAccountStatusGate(
          requiredRole: 'student',
          child: AccountSecurityPage(returnPath: '/student/profile'),
        ),
      ),
      GoRoute(
        path: '/student/profile/security/change-email',
        builder: (context, state) => const LabFlowAccountStatusGate(
          requiredRole: 'student',
          child: RequestEmailChangePage(),
        ),
      ),
      GoRoute(
        path: '/student/profile/security/change-password',
        builder: (context, state) => const LabFlowAccountStatusGate(
          requiredRole: 'student',
          child: ChangePasswordPage(),
        ),
      ),
      GoRoute(
        path: '/student/profile/about',
        builder: (context, state) => const LabFlowAccountStatusGate(
          requiredRole: 'student',
          child: AboutLabFlowPage(returnPath: '/student/profile'),
        ),
      ),

      GoRoute(
        path: '/student/notifications',
        builder: (context, state) => const LabFlowAccountStatusGate(
          requiredRole: 'student',
          child: NotificationCenterPage(role: 'student'),
        ),
      ),

      /// Area Lab Admin.
      GoRoute(
        path: '/lab-admin',
        builder: (context, state) {
          return const LabFlowAccountStatusGate(
            requiredRole: 'lab_admin',
            child: LabAdminDashboardPage(),
          );
        },
      ),
      GoRoute(
        path: '/lab-admin/notifications',
        builder: (context, state) => const LabFlowAccountStatusGate(
          requiredRole: 'lab_admin',
          child: NotificationCenterPage(role: 'lab_admin'),
        ),
      ),

      /// Profile Lab Admin.
      GoRoute(
        path: '/lab-admin/profile',
        builder: (context, state) {
          return const LabFlowAccountStatusGate(
            requiredRole: 'lab_admin',
            child: LabAdminProfilePage(),
          );
        },
      ),
      GoRoute(
        path: '/lab-admin/profile/edit',
        builder: (context, state) => const LabFlowAccountStatusGate(
          requiredRole: 'lab_admin',
          child: ProfileEditPage(returnPath: '/lab-admin/profile'),
        ),
      ),
      GoRoute(
        path: '/lab-admin/profile/guide',
        builder: (context, state) => const LabFlowAccountStatusGate(
          requiredRole: 'lab_admin',
          child: ApplicationGuidePage(
            role: 'lab_admin',
            returnPath: '/lab-admin/profile',
          ),
        ),
      ),
      GoRoute(
        path: '/lab-admin/profile/settings',
        builder: (context, state) => const LabFlowAccountStatusGate(
          requiredRole: 'lab_admin',
          child: LabFlowSettingsPage(
            role: 'lab_admin',
            returnPath: '/lab-admin/profile',
          ),
        ),
      ),
      GoRoute(
        path: '/lab-admin/profile/security',
        builder: (context, state) => const LabFlowAccountStatusGate(
          requiredRole: 'lab_admin',
          child: AccountSecurityPage(returnPath: '/lab-admin/profile'),
        ),
      ),
      GoRoute(
        path: '/lab-admin/profile/security/change-email',
        builder: (context, state) => const LabFlowAccountStatusGate(
          requiredRole: 'lab_admin',
          child: RequestEmailChangePage(),
        ),
      ),
      GoRoute(
        path: '/lab-admin/profile/security/change-password',
        builder: (context, state) => const LabFlowAccountStatusGate(
          requiredRole: 'lab_admin',
          child: ChangePasswordPage(),
        ),
      ),
      GoRoute(
        path: '/lab-admin/profile/about',
        builder: (context, state) => const LabFlowAccountStatusGate(
          requiredRole: 'lab_admin',
          child: AboutLabFlowPage(returnPath: '/lab-admin/profile'),
        ),
      ),

      /// Daftar permintaan peminjaman.
      GoRoute(
        path: '/lab-admin/borrowing',
        builder: (context, state) {
          return const LabFlowAccountStatusGate(
            requiredRole: 'lab_admin',
            child: AdminBorrowRequestsPage(),
          );
        },
      ),

      /// Detail permintaan peminjaman.
      GoRoute(
        path: '/lab-admin/borrowing/:requestId',
        builder: (context, state) {
          final requestId = state.pathParameters['requestId']!;

          return LabFlowAccountStatusGate(
            requiredRole: 'lab_admin',
            child: LabFlowBackFallback(
              fallbackPath: '/lab-admin/borrowing',
              child: AdminBorrowRequestDetailPage(requestId: requestId),
            ),
          );
        },
      ),

      /// Penugasan aset untuk request yang sudah disetujui.
      GoRoute(
        path: '/lab-admin/borrowing/:requestId/assign',
        builder: (context, state) {
          final requestId = state.pathParameters['requestId']!;

          return LabFlowAccountStatusGate(
            requiredRole: 'lab_admin',
            child: LabFlowBackFallback(
              fallbackPath:
                  '/lab-admin/borrowing/${Uri.encodeComponent(requestId)}',
              child: AssetAssignmentPage(requestId: requestId),
            ),
          );
        },
      ),

      /// Verifikasi penyerahan aset kepada mahasiswa.
      GoRoute(
        path: '/lab-admin/borrowing/:requestId/pickup',
        builder: (context, state) {
          final requestId = state.pathParameters['requestId']!;

          return LabFlowAccountStatusGate(
            requiredRole: 'lab_admin',
            child: LabFlowBackFallback(
              fallbackPath:
                  '/lab-admin/borrowing/${Uri.encodeComponent(requestId)}',
              child: PickupVerificationPage(requestId: requestId),
            ),
          );
        },
      ),

      /// Penerimaan awal barang yang dikembalikan.
      GoRoute(
        path: '/lab-admin/borrowing/:requestId/return',
        builder: (context, state) {
          final requestId = state.pathParameters['requestId']!;

          return LabFlowAccountStatusGate(
            requiredRole: 'lab_admin',
            child: LabFlowBackFallback(
              fallbackPath:
                  '/lab-admin/borrowing/${Uri.encodeComponent(requestId)}',
              child: ReturnVerificationPage(requestId: requestId),
            ),
          );
        },
      ),

      /// Pemeriksaan kondisi akhir sebelum borrowing diselesaikan.
      GoRoute(
        path: '/lab-admin/borrowing/:requestId/return/inspection',
        builder: (context, state) {
          final requestId = state.pathParameters['requestId']!;

          return LabFlowAccountStatusGate(
            requiredRole: 'lab_admin',
            child: LabFlowBackFallback(
              fallbackPath:
                  '/lab-admin/borrowing/${Uri.encodeComponent(requestId)}',
              child: ReturnConditionPage(requestId: requestId),
            ),
          );
        },
      ),

      /// Maintenance Management.
      GoRoute(
        path: '/lab-admin/maintenance',
        builder: (context, state) {
          return const LabFlowAccountStatusGate(
            requiredRole: 'lab_admin',
            child: MaintenanceListPage(),
          );
        },
      ),
      GoRoute(
        path: '/lab-admin/maintenance/create',
        builder: (context, state) {
          final labId = state.uri.queryParameters['labId'] ?? '';
          final assetId = state.uri.queryParameters['assetId'];
          final reportId = state.uri.queryParameters['reportId'];
          final description = state.uri.queryParameters['description'] ?? '';

          return LabFlowAccountStatusGate(
            requiredRole: 'lab_admin',
            child: LabFlowBackFallback(
              fallbackPath: '/lab-admin/maintenance',
              child: CreateMaintenancePage(
                laboratoryId: labId,
                initialAssetId: assetId,
                sourceType: reportId == null ? 'manual' : 'report',
                sourceId: reportId,
                initialDescription: description,
              ),
            ),
          );
        },
      ),
      GoRoute(
        path: '/lab-admin/maintenance/:maintenanceId',
        builder: (context, state) {
          final maintenanceId = state.pathParameters['maintenanceId']!;

          return LabFlowAccountStatusGate(
            requiredRole: 'lab_admin',
            child: LabFlowBackFallback(
              fallbackPath: '/lab-admin/maintenance',
              child: MaintenanceDetailPage(maintenanceId: maintenanceId),
            ),
          );
        },
      ),

      /// Report Management.
      GoRoute(
        path: '/lab-admin/reports',
        builder: (context, state) {
          return const LabFlowAccountStatusGate(
            requiredRole: 'lab_admin',
            child: AdminReportListPage(),
          );
        },
      ),
      GoRoute(
        path: '/lab-admin/reports/:reportId',
        builder: (context, state) {
          final reportId = state.pathParameters['reportId']!;

          return LabFlowAccountStatusGate(
            requiredRole: 'lab_admin',
            child: LabFlowBackFallback(
              fallbackPath: '/lab-admin/reports',
              child: AdminReportDetailPage(reportId: reportId),
            ),
          );
        },
      ),

      /// Inventory Lab Admin.
      GoRoute(
        path: '/lab-admin/assets',
        builder: (context, state) {
          return const LabFlowAccountStatusGate(
            requiredRole: 'lab_admin',
            child: AssetManagementPage(),
          );
        },
      ),
      GoRoute(
        path: '/lab-admin/assets/create',
        builder: (context, state) {
          return const LabFlowAccountStatusGate(
            requiredRole: 'lab_admin',
            child: LabFlowBackFallback(
              fallbackPath: '/lab-admin/assets',
              child: CreateAssetPage(),
            ),
          );
        },
      ),
      GoRoute(
        path: '/lab-admin/assets/:assetId',
        builder: (context, state) {
          final assetId = state.pathParameters['assetId']!;

          return LabFlowAccountStatusGate(
            requiredRole: 'lab_admin',
            child: LabFlowBackFallback(
              fallbackPath: '/lab-admin/assets',
              child: AssetDetailPage(assetId: assetId),
            ),
          );
        },
      ),
      GoRoute(
        path: '/lab-admin/assets/:assetId/edit',
        builder: (context, state) {
          final assetId = state.pathParameters['assetId']!;

          return LabFlowAccountStatusGate(
            requiredRole: 'lab_admin',
            child: LabFlowBackFallback(
              fallbackPath: '/lab-admin/assets/${Uri.encodeComponent(assetId)}',
              child: EditAssetPage(assetId: assetId),
            ),
          );
        },
      ),
    ],
  );
}
