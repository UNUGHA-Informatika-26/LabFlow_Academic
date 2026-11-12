import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../profile/presentation/widgets/profile_navigation_widgets.dart';
import '../../data/student_service.dart';
import '../../domain/student_models.dart';
import '../cubit/student_data_state.dart';
import '../cubit/student_profile_cubit.dart';
import '../widgets/student_bottom_navigation.dart';
import '../widgets/student_ui.dart';

class StudentProfilePage extends StatelessWidget {
  const StudentProfilePage({this.service, super.key});

  final StudentService? service;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => StudentProfileCubit(service ?? StudentService())..load(),
      child: const _StudentProfileView(),
    );
  }
}

class _StudentProfileView extends StatelessWidget {
  const _StudentProfileView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: studentPaper,
      bottomNavigationBar: const StudentBottomNavigation(currentIndex: 4),
      body: SafeArea(
        bottom: false,
        child:
            BlocBuilder<StudentProfileCubit, StudentDataState<StudentProfile>>(
              builder: (context, state) {
                if (state.status == StudentLoadStatus.initial ||
                    state.status == StudentLoadStatus.loading) {
                  return const StudentLoading(
                    message: 'Memuat profil mahasiswa.',
                  );
                }
                if (state.status == StudentLoadStatus.failure ||
                    state.data == null) {
                  return StudentErrorState(
                    message: state.errorMessage,
                    onRetry: context.read<StudentProfileCubit>().load,
                  );
                }
                return _content(context, state.data!);
              },
            ),
      ),
    );
  }

  Widget _content(BuildContext context, StudentProfile profile) {
    return RefreshIndicator(
      onRefresh: context.read<StudentProfileCubit>().load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
        children: [
          const Text(
            'Profil',
            style: TextStyle(
              fontSize: 31,
              height: 1.1,
              fontWeight: FontWeight.w900,
              color: studentInk,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(23),
            decoration: BoxDecoration(
              color: studentSoftLime,
              borderRadius: BorderRadius.circular(24),
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
                          errorBuilder: (_, _, _) =>
                              _initialAvatar(profile.initials),
                        )
                      : _initialAvatar(profile.initials),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 23,
                          height: 1.15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Student',
                          style: TextStyle(fontSize: 12, color: studentMuted),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        profile.email,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: studentMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          ProfileMenuTile(
            icon: Icons.manage_accounts_outlined,
            title: 'Edit Profil',
            onTap: () async {
              final updated = await context.push<bool>('/student/profile/edit');
              if (updated == true && context.mounted) {
                await context.read<StudentProfileCubit>().load();
              }
            },
          ),
          ProfileMenuTile(
            icon: Icons.security_outlined,
            title: 'Keamanan Akun',
            onTap: () => context.push('/student/profile/security'),
          ),
          ProfileMenuTile(
            icon: Icons.menu_book_outlined,
            title: 'Panduan Aplikasi',
            onTap: () => context.push('/student/profile/guide'),
          ),
          ProfileMenuTile(
            icon: Icons.tune_rounded,
            title: 'Pengaturan',
            onTap: () => context.push('/student/profile/settings'),
          ),
          ProfileMenuTile(
            icon: Icons.science_outlined,
            title: 'Tentang LabFlow',
            onTap: () => context.push('/student/profile/about'),
          ),
          const SizedBox(height: 16),
          _identityTile('NIM', profile.nim),
          _identityTile('Program Studi', profile.studyProgram),
          _identityTile('Semester', profile.semester?.toString()),
          _identityTile('Nomor HP', profile.phoneNumber),
          const SizedBox(height: 22),
          SizedBox(
            height: 56,
            child: OutlinedButton.icon(
              onPressed: () async {
                final confirmed = await _confirmLogout(context);
                if (confirmed != true || !context.mounted) return;
                await context.read<StudentProfileCubit>().signOut();
                if (!context.mounted) return;
                context.go('/login');
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: studentInk,
                side: const BorderSide(color: studentBorder),
                backgroundColor: Colors.white,
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.logout_rounded, size: 22),
              label: const Text(
                'Keluar',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Center(
            child: Text(
              'LabFlow · Versi 1.0.0',
              style: TextStyle(fontSize: 12, color: studentMuted),
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
    color: studentSoftLime,
    child: Text(
      initials,
      style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
    ),
  );

  Widget _identityTile(String label, String? value) => ListTile(
    dense: true,
    title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    trailing: Text(value?.trim().isNotEmpty == true ? value! : 'Belum diisi'),
  );

  Future<bool?> _confirmLogout(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Keluar dari LabFlow?'),
        content: const Text(
          'Anda perlu masuk kembali untuk mengakses layanan laboratorium.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Tetap di Sini'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: studentPinkText,
              foregroundColor: Colors.white,
            ),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
  }
}
