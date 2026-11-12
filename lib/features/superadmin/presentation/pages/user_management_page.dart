import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/presentation/notifications/labflow_notification.dart';
import '../../../../shared/presentation/states/labflow_connection_error_state.dart';
import '../../../../shared/presentation/states/labflow_loading_state.dart';
import '../../../../shared/presentation/states/labflow_no_search_results_state.dart';
import '../../../auth/domain/user_profile.dart';
import '../../data/user_management_service.dart';
import '../cubit/user_directory_cubit.dart';
import '../widgets/superadmin_bottom_navigation.dart';

enum _UserRoleFilter { all, student, labAdmin, superadmin }

enum _UserStatusFilter { all, active, suspended }

class UserManagementPage extends StatelessWidget {
  const UserManagementPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => UserDirectoryCubit(UserManagementService())..start(),
    child: const _UserManagementView(),
  );
}

class _UserManagementView extends StatefulWidget {
  const _UserManagementView();

  @override
  State<_UserManagementView> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<_UserManagementView> {
  final TextEditingController _searchController = TextEditingController();
  _UserRoleFilter _selectedRole = _UserRoleFilter.all;
  _UserStatusFilter _selectedStatus = _UserStatusFilter.all;
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F9EF),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: _buildHeader(),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildSearchBar(),
            ),
            const SizedBox(height: 18),
            SizedBox(height: 48, child: _buildRoleFilters()),
            const SizedBox(height: 12),
            Expanded(
              child: BlocBuilder<UserDirectoryCubit, UserDirectoryState>(
                builder: (context, state) {
                  if (state is UserDirectoryLoading) {
                    return const LabFlowLoadingState(
                      title: 'Memuat pengguna',
                      message: 'Mengambil daftar pengguna terbaru.',
                    );
                  }
                  if (state is UserDirectoryFailure) {
                    return const LabFlowConnectionErrorState(
                      title: 'Pengguna tidak dapat dimuat',
                      message:
                          'Data pengguna tidak dapat diambil saat ini. '
                          'Periksa koneksi Anda lalu coba lagi.',
                    );
                  }
                  final users = (state as UserDirectoryLoaded).users;
                  if (users.isEmpty) {
                    return _buildEmptyState();
                  }
                  final filteredUsers = state.visibleUsers;
                  if (filteredUsers.isEmpty) {
                    return const LabFlowNoSearchResultsState(
                      title: 'Pengguna tidak ditemukan',
                      message:
                          'Coba ubah pencarian atau filter yang digunakan.',
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                    children: [
                      Text(
                        '${filteredUsers.length} pengguna',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF7A8190),
                        ),
                      ),
                      const SizedBox(height: 20),
                      for (
                        int index = 0;
                        index < filteredUsers.length;
                        index++
                      ) ...[
                        _buildUserRow(filteredUsers[index]),
                        if (index != filteredUsers.length - 1)
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: Color(0xFFDDE2D5),
                          ),
                      ],
                      const SizedBox(height: 16),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const SuperadminBottomNavigation(currentIndex: 2),
    );
  }

  /// Header halaman Pengguna.
  Widget _buildHeader() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Pengguna',
            style: TextStyle(
              fontSize: 30,
              height: 1,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111111),
            ),
          ),
        ),
        const SizedBox(width: 16),
        IconButton(
          tooltip: 'Permohonan Ubah Email',
          onPressed: () => context.push('/superadmin/email-requests'),
          icon: const Icon(Icons.mark_email_unread_outlined, size: 26, color: Color(0xFF111111)),
        ),
        const SizedBox(width: 8),
        Material(
          color: Colors.white,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _openCreateUser,
            child: const SizedBox(
              width: 52,
              height: 52,
              child: Icon(
                Icons.person_add_alt_1_rounded,
                size: 26,
                color: Color(0xFF111111),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Search + tombol filter status.
  Widget _buildSearchBar() {
    final statusFilterActive = _selectedStatus != _UserStatusFilter.all;
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFDDE2D5)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          const Icon(Icons.search_rounded, size: 24, color: Color(0xFF111111)),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: context.read<UserDirectoryCubit>().setQuery,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Cari nama atau email...',
                hintStyle: TextStyle(fontSize: 14, color: Color(0xFF8B929F)),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Filter status',
            onPressed: _openStatusFilter,
            icon: Icon(
              Icons.tune_rounded,
              color: statusFilterActive
                  ? const Color(0xFF6C9B00)
                  : const Color(0xFF111111),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  /// Filter Role.
  Widget _buildRoleFilters() {
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        _buildRoleChip(label: 'Semua', value: _UserRoleFilter.all),
        const SizedBox(width: 8),
        _buildRoleChip(label: 'Student', value: _UserRoleFilter.student),
        const SizedBox(width: 8),
        _buildRoleChip(label: 'Lab Admin', value: _UserRoleFilter.labAdmin),
        const SizedBox(width: 8),
        _buildRoleChip(label: 'Superadmin', value: _UserRoleFilter.superadmin),
      ],
    );
  }

  Widget _buildRoleChip({
    required String label,
    required _UserRoleFilter value,
  }) {
    final selected = _selectedRole == value;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () {
        setState(() {
          _selectedRole = value;
        });
        context.read<UserDirectoryCubit>().setRole(switch (value) {
          _UserRoleFilter.all => 'all',
          _UserRoleFilter.student => 'student',
          _UserRoleFilter.labAdmin => 'lab_admin',
          _UserRoleFilter.superadmin => 'superadmin',
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF111111) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFF111111) : const Color(0xFFDDE2D5),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected
                  ? const Color(0xFFB9F33D)
                  : const Color(0xFF111111),
            ),
          ),
        ),
      ),
    );
  }

  /// Row pengguna:
  ///
  /// Avatar - Nama - Role + Email - Status - Arrow.
  Widget _buildUserRow(UserProfile user) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        _openEditUser(user);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFEAFBCB),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF111111)),
              ),
              child: Text(
                _initials(user.fullName),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111111),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.fullName.isEmpty ? 'Tanpa Nama' : user.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111111),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${_roleLabel(user.role)} · ${user.email}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF7A8190),
                    ),
                  ),
                  const SizedBox(height: 7),
                  _buildStatusBadge(user.isActive),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right_rounded,
              size: 24,
              color: Color(0xFF111111),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(bool isActive) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFE5F6EC) : const Color(0xFFFFE1E1),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          isActive ? 'Active' : 'Suspended',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isActive ? const Color(0xFF188A55) : const Color(0xFFC93434),
          ),
        ),
      ),
    );
  }

  /// Filter status melalui bottom sheet.
  Future<void> _openStatusFilter() async {
    final result = await showModalBottomSheet<_UserStatusFilter>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF6F9EF),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Filter Status',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111111),
                  ),
                ),
                const SizedBox(height: 16),
                _buildStatusFilterOption(
                  context: context,
                  value: _UserStatusFilter.all,
                  label: 'Semua Status',
                  icon: Icons.apps_rounded,
                ),
                _buildStatusFilterOption(
                  context: context,
                  value: _UserStatusFilter.active,
                  label: 'Active',
                  icon: Icons.check_circle_outline_rounded,
                ),
                _buildStatusFilterOption(
                  context: context,
                  value: _UserStatusFilter.suspended,
                  label: 'Suspended',
                  icon: Icons.block_rounded,
                ),
              ],
            ),
          ),
        );
      },
    );
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      _selectedStatus = result;
    });
    context.read<UserDirectoryCubit>().setStatus(switch (result) {
      _UserStatusFilter.all => 'all',
      _UserStatusFilter.active => 'active',
      _UserStatusFilter.suspended => 'suspended',
    });
  }

  Widget _buildStatusFilterOption({
    required BuildContext context,
    required _UserStatusFilter value,
    required String label,
    required IconData icon,
  }) {
    final selected = _selectedStatus == value;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: selected ? const Color(0xFFB9F33D) : Colors.white,
        foregroundColor: const Color(0xFF111111),
        child: Icon(icon),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      trailing: selected ? const Icon(Icons.check_rounded) : null,
      onTap: () {
        Navigator.of(context).pop(value);
      },
    );
  }

  /// Membuka Create User.
  Future<void> _openCreateUser() async {
    final created = await context.push<bool>('/superadmin/users/create');
    if (!mounted) {
      return;
    }
    if (created == true) {
      _showSuccessNotification(
        title: 'Pengguna dibuat',
        message: 'Akun pengguna baru berhasil ditambahkan ke LabFlow.',
      );
    }
  }

  /// Membuka Edit User dan menangani hasil perubahan.
  Future<void> _openEditUser(UserProfile user) async {
    final result = await context.push<String>(
      '/superadmin/users/${user.uid}/edit',
    );
    if (!mounted) {
      return;
    }
    switch (result) {
      case 'updated':
        _showSuccessNotification(
          title: 'Pengguna diperbarui',
          message: 'Data ${user.fullName} berhasil diperbarui.',
        );
        break;
      case 'suspended':
        _showWarningNotification(
          title: 'Pengguna dinonaktifkan',
          message: 'Akun ${user.fullName} berhasil dinonaktifkan.',
        );
        break;
      case 'activated':
        _showSuccessNotification(
          title: 'Pengguna diaktifkan',
          message: 'Akun ${user.fullName} berhasil diaktifkan kembali.',
        );
        break;
    }
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline_rounded, size: 56),
            SizedBox(height: 16),
            Text(
              'Belum ada pengguna',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 8),
            Text(
              'Tambahkan pengguna pertama melalui tombol di atas.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ],
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
      return '?';
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

  String _roleLabel(String role) {
    switch (role) {
      case 'student':
        return 'Student';
      case 'lab_admin':
        return 'Lab Admin';
      case 'superadmin':
        return 'Superadmin';
      default:
        return role;
    }
  }

  void _showSuccessNotification({
    required String title,
    required String message,
  }) {
    showLabFlowNotification(
      context: context,
      title: title,
      message: message,
      type: LabFlowNotificationType.success,
    );
  }

  void _showWarningNotification({
    required String title,
    required String message,
  }) {
    showLabFlowNotification(
      context: context,
      title: title,
      message: message,
      type: LabFlowNotificationType.warning,
    );
  }
}
