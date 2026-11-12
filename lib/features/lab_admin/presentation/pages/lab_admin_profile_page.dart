import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/presentation/notifications/labflow_notification.dart';
import '../../../../shared/presentation/states/labflow_connection_error_state.dart';
import '../../../../shared/presentation/states/labflow_loading_state.dart';
import '../../../profile/presentation/widgets/profile_navigation_widgets.dart';
import '../../data/lab_admin_profile_service.dart';
import '../../domain/lab_admin_profile.dart';
import '../cubit/lab_admin_profile_cubit.dart';
import '../cubit/lab_admin_profile_state.dart';
import '../widgets/lab_admin_bottom_navigation.dart';

class LabAdminProfilePage extends StatelessWidget {
  const LabAdminProfilePage({this.service, super.key});

  final LabAdminProfileService? service;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          LabAdminProfileCubit(service ?? LabAdminProfileService())..load(),
      child: const _LabAdminProfileView(),
    );
  }
}

class _LabAdminProfileView extends StatelessWidget {
  const _LabAdminProfileView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<LabAdminProfileCubit, LabAdminProfileState>(
      listenWhen: (previous, current) =>
          previous.actionStatus != current.actionStatus &&
          current.actionStatus != LabAdminProfileActionStatus.idle,
      listener: (context, state) {
        if (state.actionStatus == LabAdminProfileActionStatus.signedOut) {
          context.go('/login');
          return;
        }

        if (state.actionStatus == LabAdminProfileActionStatus.failure) {
          showLabFlowNotification(
            context: context,
            title: 'Logout gagal',
            message: state.actionMessage,
            type: LabFlowNotificationType.error,
          );

          context.read<LabAdminProfileCubit>().clearAction();
        }
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: const Color(0xFFF6F9EF),
          bottomNavigationBar: const LabAdminBottomNavigation(currentIndex: 4),
          body: SafeArea(bottom: false, child: _buildBody(context, state)),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, LabAdminProfileState state) {
    if (state.status == LabAdminProfileStatus.initial ||
        state.status == LabAdminProfileStatus.loading) {
      return const LabFlowLoadingState(
        title: 'Memuat profil',
        message: 'Menyiapkan informasi akun Lab Admin.',
      );
    }

    if (state.status == LabAdminProfileStatus.failure ||
        state.profile == null) {
      return LabFlowConnectionErrorState(
        title: 'Profil tidak dapat dimuat',
        message: state.errorMessage.isEmpty
            ? 'Informasi profil tidak tersedia.'
            : state.errorMessage,
      );
    }

    final profile = state.profile!;

    return RefreshIndicator(
      onRefresh: context.read<LabAdminProfileCubit>().load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
        children: [
          const Text(
            'Profil',
            style: TextStyle(
              fontSize: 31,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111111),
            ),
          ),
          const SizedBox(height: 20),
          _profileHero(profile),
          const SizedBox(height: 16),
          ProfileMenuTile(
            icon: Icons.edit_outlined,
            title: 'Edit Profil',
            onTap: () async {
              final updated = await context.push<bool>(
                '/lab-admin/profile/edit',
              );
              if (updated == true && context.mounted) {
                await context.read<LabAdminProfileCubit>().load();
              }
            },
          ),
          ProfileMenuTile(
            icon: Icons.security_outlined,
            title: 'Keamanan Akun',
            onTap: () => context.push('/lab-admin/profile/security'),
          ),
          ProfileMenuTile(
            icon: Icons.menu_book_outlined,
            title: 'Panduan Aplikasi',
            onTap: () => context.push('/lab-admin/profile/guide'),
          ),
          ProfileMenuTile(
            icon: Icons.tune_rounded,
            title: 'Pengaturan',
            onTap: () => context.push('/lab-admin/profile/settings'),
          ),
          ProfileMenuTile(
            icon: Icons.science_outlined,
            title: 'Tentang LabFlow',
            onTap: () => context.push('/lab-admin/profile/about'),
          ),
          const SizedBox(height: 16),
          _sectionTitle('Informasi Akun'),
          const SizedBox(height: 10),
          _infoCard(
            icon: Icons.email_outlined,
            label: 'Email',
            value: profile.email.isEmpty ? '-' : profile.email,
          ),
          const SizedBox(height: 10),
          _infoCard(
            icon: Icons.phone_outlined,
            label: 'Nomor HP',
            value: profile.phoneNumber?.trim().isNotEmpty == true
                ? profile.phoneNumber!
                : 'Belum diisi',
          ),
          const SizedBox(height: 10),
          _infoCard(
            icon: Icons.badge_outlined,
            label: 'NIP',
            value: profile.nip?.trim().isNotEmpty == true
                ? profile.nip!
                : 'Belum diisi',
          ),
          const SizedBox(height: 10),
          _infoCard(
            icon: Icons.school_outlined,
            label: 'NIDN',
            value: profile.nidn?.trim().isNotEmpty == true
                ? profile.nidn!
                : 'Belum diisi',
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _smallInfoCard(
                  icon: Icons.admin_panel_settings_outlined,
                  label: 'Role',
                  value: _roleLabel(profile.role),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _smallInfoCard(
                  icon: Icons.verified_user_outlined,
                  label: 'Status',
                  value: _statusLabel(profile.status),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _sectionTitle('Laboratorium'),
          const SizedBox(height: 10),
          if (profile.laboratories.isEmpty)
            _emptyLaboratoryCard()
          else
            ...profile.laboratories.map(
              (laboratory) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _laboratoryCard(laboratory),
              ),
            ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEAFBCB),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Akses inventaris, peminjaman, laporan, dan maintenance '
                    'dibatasi sesuai membership laboratorium aktif.',
                    style: TextStyle(height: 1.4, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton.icon(
              onPressed: state.isSigningOut
                  ? null
                  : () async {
                      final confirmed = await _confirmLogout(context);

                      if (confirmed != true || !context.mounted) {
                        return;
                      }

                      await context.read<LabAdminProfileCubit>().signOut();
                    },
              icon: state.isSigningOut
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFB42318),
                      ),
                    )
                  : const Icon(Icons.logout_rounded),
              label: const Text(
                'Keluar dari Akun',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB42318),
                side: const BorderSide(color: Color(0xFFB42318)),
                shape: const StadiumBorder(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'LabFlow · Laboratory Asset & Service Management System',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF8A9186)),
          ),
        ],
      ),
    );
  }

  Widget _profileHero(LabAdminProfile profile) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(23),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          ClipOval(
            child: profile.profilePhotoUrl?.isNotEmpty == true
                ? Image.network(
                    profile.profilePhotoUrl!,
                    width: 82,
                    height: 82,
                    cacheWidth: 246,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _initialAvatar(profile.initials),
                  )
                : _initialAvatar(profile.initials),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Lab Admin',
                  style: TextStyle(fontSize: 13, color: Color(0xFFB8BCB3)),
                ),
                const SizedBox(height: 4),
                Text(
                  profile.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 23,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${profile.laboratories.length} laboratorium aktif',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFFB8BCB3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _initialAvatar(String initials) => Container(
    width: 82,
    height: 82,
    alignment: Alignment.center,
    color: const Color(0xFFB9F33D),
    child: Text(
      initials,
      style: const TextStyle(
        fontSize: 27,
        fontWeight: FontWeight.w900,
        color: Color(0xFF111111),
      ),
    ),
  );

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE2D5)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 21, color: const Color(0xFF6B7280)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF7A8190),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallInfoCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE2D5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFF6B7280)),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF7A8190)),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _laboratoryCard(LabAdminProfileLaboratory laboratory) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDDE2D5)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFEAFBCB),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.science_outlined, color: Color(0xFF111111)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  laboratory.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${laboratory.code} · ${laboratory.location}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF7A8190),
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.verified_rounded,
            size: 20,
            color: Color(0xFF188A55),
          ),
        ],
      ),
    );
  }

  Widget _emptyLaboratoryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDDE2D5)),
      ),
      child: const Text(
        'Belum ada membership laboratorium aktif.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(0xFF7A8190), fontWeight: FontWeight.w600),
      ),
    );
  }

  Future<bool?> _confirmLogout(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFFF6F9EF),
          title: const Text('Keluar dari akun?'),
          content: const Text(
            'Sesi Lab Admin pada perangkat ini akan diakhiri.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB42318),
                foregroundColor: Colors.white,
              ),
              child: const Text('Keluar'),
            ),
          ],
        );
      },
    );
  }
}

String _roleLabel(String value) {
  switch (value) {
    case 'lab_admin':
      return 'Lab Admin';
    case 'superadmin':
      return 'Superadmin';
    case 'student':
      return 'Student';
    default:
      return value;
  }
}

String _statusLabel(String value) {
  switch (value) {
    case 'active':
      return 'Aktif';
    case 'inactive':
      return 'Tidak Aktif';
    case 'suspended':
      return 'Ditangguhkan';
    default:
      return value;
  }
}
