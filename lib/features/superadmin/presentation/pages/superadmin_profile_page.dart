import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/presentation/dialogs/labflow_confirmation_dialog.dart';
import '../../../../shared/presentation/states/labflow_access_denied_state.dart';
import '../../../../shared/presentation/states/labflow_connection_error_state.dart';
import '../../../../shared/presentation/states/labflow_loading_state.dart';
import '../../../../shared/presentation/states/labflow_suspended_account_state.dart';
import '../../../profile/presentation/widgets/profile_navigation_widgets.dart';
import '../../../auth/data/auth_service.dart';
import '../../../auth/domain/user_profile.dart';
import '../cubit/superadmin_profile_cubit.dart';
import '../widgets/superadmin_bottom_navigation.dart';

class SuperadminProfilePage extends StatelessWidget {
  const SuperadminProfilePage({this.authService, super.key});

  final AuthService? authService;

  @override
  Widget build(BuildContext context) => RepositoryProvider<AuthService>(
    create: (_) => authService ?? AuthService(),
    child: BlocProvider(
      create: (context) =>
          SuperadminProfileCubit(context.read<AuthService>())..load(),
      child: const _SuperadminProfileView(),
    ),
  );
}

class _SuperadminProfileView extends StatefulWidget {
  const _SuperadminProfileView();

  @override
  State<_SuperadminProfileView> createState() => _SuperadminProfilePageState();
}

class _SuperadminProfilePageState extends State<_SuperadminProfileView> {
  Future<void> _logout() async {
    final confirmed = await showLogoutConfirmationDialog(context: context);

    if (!confirmed || !mounted) {
      return;
    }

    await context.read<AuthService>().signOut();

    if (!mounted) {
      return;
    }

    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SuperadminProfileCubit, SuperadminProfileState>(
      builder: (context, state) => Scaffold(
        backgroundColor: const Color(0xFFF6F9EF),
        body: SafeArea(
          bottom: false,
          child: switch (state) {
            SuperadminProfileLoading() => const LabFlowLoadingState(
              title: 'Memuat profile',
              message: 'Mengambil informasi akun Superadmin.',
            ),
            SuperadminProfileFailure(:final isSuspended) when isSuspended =>
              LabFlowSuspendedAccountState(
                onAction: () => context.go('/login'),
              ),
            SuperadminProfileFailure() => LabFlowConnectionErrorState(
              title: 'Profile tidak dapat dimuat',
              message:
                  'Informasi akun tidak dapat diambil saat ini. '
                  'Periksa koneksi Anda lalu coba lagi.',
              onRetry: context.read<SuperadminProfileCubit>().load,
            ),
            SuperadminProfileLoaded(:final profile)
                when !profile.isSuperadmin =>
              LabFlowAccessDeniedState(
                title: 'Akses Superadmin ditolak',
                message:
                    'Akun ini tidak memiliki role Superadmin sehingga '
                    'tidak dapat mengakses halaman Profile Superadmin.',
                actionLabel: 'Ke Halaman Saya',
                onAction: () => _goToOwnHome(profile),
              ),
            SuperadminProfileLoaded(:final profile) => _buildContent(profile),
          },
        ),
        bottomNavigationBar: const SuperadminBottomNavigation(currentIndex: 4),
      ),
    );
  }

  Future<void> _goToOwnHome(UserProfile profile) async {
    switch (profile.role) {
      case 'lab_admin':
        context.go('/lab-admin');
        return;

      case 'student':
        context.go('/student');
        return;

      case 'superadmin':
        context.go('/superadmin');
        return;

      default:
        await context.read<AuthService>().signOut();

        if (!mounted) {
          return;
        }

        context.go('/login');
    }
  }

  Widget _buildContent(UserProfile profile) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Profil',
            style: TextStyle(
              fontSize: 31,
              height: 1,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111111),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Informasi akun Superadmin LabFlow.',
            style: TextStyle(fontSize: 14, color: Color(0xFF7A8190)),
          ),
          const SizedBox(height: 28),
          _buildIdentityCard(profile),
          const SizedBox(height: 18),
          ProfileMenuTile(
            icon: Icons.edit_outlined,
            title: 'Edit Profil',
            onTap: () async {
              final updated = await context.push<bool>(
                '/superadmin/profile/edit',
              );
              if (updated == true && mounted) {
                await context.read<SuperadminProfileCubit>().load();
              }
            },
          ),
          ProfileMenuTile(
            icon: Icons.security_outlined,
            title: 'Keamanan Akun',
            onTap: () => context.push('/superadmin/profile/security'),
          ),
          ProfileMenuTile(
            icon: Icons.menu_book_outlined,
            title: 'Panduan Aplikasi',
            onTap: () => context.push('/superadmin/profile/guide'),
          ),
          ProfileMenuTile(
            icon: Icons.tune_rounded,
            title: 'Pengaturan',
            onTap: () => context.push('/superadmin/profile/settings'),
          ),
          ProfileMenuTile(
            icon: Icons.science_outlined,
            title: 'Tentang LabFlow',
            onTap: () => context.push('/superadmin/profile/about'),
          ),
          const SizedBox(height: 18),
          _buildAccountInformation(profile),
          const SizedBox(height: 22),
          _buildLogoutButton(),
          const SizedBox(height: 18),
          const Center(
            child: Text(
              'LabFlow · Versi 1.0.0',
              style: TextStyle(fontSize: 12, color: Color(0xFF7A8190)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityCard(UserProfile profile) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          ClipOval(
            child: profile.profilePhotoUrl?.isNotEmpty == true
                ? Image.network(
                    profile.profilePhotoUrl!,
                    width: 80,
                    height: 80,
                    cacheWidth: 240,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        _avatarFallback(profile.fullName),
                  )
                : _avatarFallback(profile.fullName),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.fullName.isEmpty ? 'Superadmin' : profile.fullName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 23,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  profile.email,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFFB7BAB4),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB9F33D),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Superadmin',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111111),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarFallback(String name) => Container(
    width: 80,
    height: 80,
    alignment: Alignment.center,
    color: const Color(0xFFB9F33D),
    child: Text(
      _initials(name),
      style: const TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: Color(0xFF111111),
      ),
    ),
  );

  Widget _buildAccountInformation(UserProfile profile) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E6DC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Informasi Akun',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111111),
            ),
          ),
          const SizedBox(height: 20),
          _buildInformationRow(
            icon: Icons.person_outline_rounded,
            label: 'Nama lengkap',
            value: profile.fullName,
          ),
          _buildDivider(),
          _buildInformationRow(
            icon: Icons.email_outlined,
            label: 'Email',
            value: profile.email,
          ),
          _buildDivider(),
          _buildInformationRow(
            icon: Icons.phone_outlined,
            label: 'Nomor HP',
            value: profile.phoneNumber?.trim().isNotEmpty == true
                ? profile.phoneNumber!
                : 'Belum diisi',
          ),
          _buildDivider(),
          _buildInformationRow(
            icon: Icons.admin_panel_settings_outlined,
            label: 'Role',
            value: 'Superadmin',
          ),
          _buildDivider(),
          _buildInformationRow(
            icon: Icons.verified_user_outlined,
            label: 'Status',
            value: profile.isActive ? 'Active' : profile.status,
          ),
          _buildDivider(),
          _buildInformationRow(
            icon: Icons.fingerprint_rounded,
            label: 'UID',
            value: profile.uid,
            selectable: true,
          ),
        ],
      ),
    );
  }

  Widget _buildInformationRow({
    required IconData icon,
    required String label,
    required String value,
    bool selectable = false,
  }) {
    final valueWidget = selectable
        ? SelectableText(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111111),
            ),
          )
        : Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111111),
            ),
          );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(
            color: Color(0xFFEAFBCB),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 21, color: const Color(0xFF111111)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF7A8190),
                ),
              ),
              const SizedBox(height: 4),
              valueWidget,
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Divider(height: 1, color: Color(0xFFE5E9DF)),
    );
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton.icon(
        onPressed: _logout,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFBD3232),
          side: const BorderSide(color: Color(0xFFBD3232)),
          shape: const StadiumBorder(),
        ),
        icon: const Icon(Icons.logout_rounded, size: 20),
        label: const Text(
          'Keluar dari LabFlow',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) {
      return 'SA';
    }

    if (parts.length == 1) {
      final value = parts.first;

      if (value.length == 1) {
        return value.toUpperCase();
      }

      return value.substring(0, 2).toUpperCase();
    }

    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}
