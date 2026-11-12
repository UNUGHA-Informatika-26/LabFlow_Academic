import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/presentation/notifications/labflow_notification.dart';
import '../../../../shared/presentation/states/labflow_connection_error_state.dart';
import '../../../../shared/presentation/states/labflow_loading_state.dart';
import '../../../../core/validators/auth_validator.dart';
import '../../../auth/domain/user_profile.dart';
import '../../data/user_management_service.dart';
import '../../data/activity_log_service.dart';
import '../cubit/user_management_action_cubit.dart';
import '../cubit/user_detail_cubit.dart';

class EditUserPage extends StatelessWidget {
  const EditUserPage({
    required this.userId,
    this.actionCubit,
    this.detailCubit,
    super.key,
  });
  final String userId;
  final UserManagementActionCubit? actionCubit;
  final UserDetailCubit? detailCubit;

  @override
  Widget build(BuildContext context) {
    if (actionCubit != null && detailCubit != null) {
      return MultiBlocProvider(
        providers: [
          BlocProvider.value(value: actionCubit!),
          BlocProvider.value(value: detailCubit!),
        ],
        child: _EditUserView(userId: userId),
      );
    }
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => UserManagementActionCubit(
            UserManagementService(),
            ActivityLogService(),
          ),
        ),
        BlocProvider(
          create: (_) => UserDetailCubit(UserManagementService())..load(userId),
        ),
      ],
      child: _EditUserView(userId: userId),
    );
  }
}

class _EditUserView extends StatefulWidget {
  const _EditUserView({required this.userId});

  final String userId;

  @override
  State<_EditUserView> createState() => _EditUserPageState();
}

class _EditUserPageState extends State<_EditUserView> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _nimController = TextEditingController();
  final TextEditingController _programController = TextEditingController();
  final TextEditingController _semesterController = TextEditingController();
  final TextEditingController _nipController = TextEditingController();
  final TextEditingController _nidnController = TextEditingController();
  bool _initialised = false;
  bool get _isSaving => context.read<UserManagementActionCubit>().state;
  bool get _isChangingStatus => _isSaving;
  String _role = 'student';
  String _status = 'active';

  /// Menyimpan kondisi awal pengguna.
  ///
  /// Data ini diperlukan agar Activity Log dapat mengetahui
  /// apakah nama atau role benar-benar berubah.
  String _originalFullName = '';
  String _originalRole = 'student';
  String _originalEmail = '';
  UserProfile? _originalProfile;

  bool get _isDirty {
    final original = _originalProfile;
    if (original == null) return false;
    String norm(String? value) => value?.trim() ?? '';
    final desiredNim = _role == 'student' ? norm(_nimController.text) : '';
    final desiredProgram =
        _role == 'student' ? norm(_programController.text) : '';
    final desiredSemester =
        _role == 'student' ? int.tryParse(_semesterController.text.trim()) : null;
    final desiredNip = _role == 'lab_admin' ? norm(_nipController.text) : '';
    final desiredNidn = _role == 'lab_admin' ? norm(_nidnController.text) : '';
    return norm(original.fullName) != norm(_nameController.text) ||
        original.role != _role ||
        original.status != _status ||
        norm(original.phoneNumber) != norm(_phoneController.text) ||
        norm(original.nim) != desiredNim ||
        norm(original.studyProgram) != desiredProgram ||
        original.semester != desiredSemester ||
        norm(original.nip) != desiredNip ||
        norm(original.nidn) != desiredNidn;
  }
  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _nimController.dispose();
    _programController.dispose();
    _semesterController.dispose();
    _nipController.dispose();
    _nidnController.dispose();
    super.dispose();
  }

  /// Mengisi form pertama kali dari data Firestore.
  ///
  /// Data awal juga disimpan sebagai pembanding ketika
  /// pengguna menekan tombol Simpan Perubahan.
  void _fillForm(UserProfile profile) {
    if (_initialised) return;
    _nameController.text = profile.fullName;
    _emailController.text = profile.email;
    _phoneController.text = profile.phoneNumber ?? '';
    _nimController.text = profile.nim ?? '';
    _programController.text = profile.studyProgram ?? '';
    _semesterController.text = profile.semester?.toString() ?? '';
    _nipController.text = profile.nip ?? '';
    _nidnController.text = profile.nidn ?? '';
    _role = profile.role;
    _status = profile.status;
    _originalFullName = profile.fullName;
    _originalRole = profile.role;
    _originalEmail = profile.email;
    _originalProfile = profile;
    _initialised = true;
  }

  /// Menyimpan perubahan nama dan/atau role pengguna.
  ///
  /// Activity Log hanya dibuat setelah operasi Firestore
  /// berhasil dilakukan.
  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid || _isSaving || _isChangingStatus || !_isDirty) {
      return;
    }
    try {
      final newFullName = _nameController.text.trim();
      final oldFullName = _originalFullName.trim();
      final oldRole = _originalRole;
      final newRole = _role;

      /// Menyimpan perubahan utama terlebih dahulu.
      await context.read<UserManagementActionCubit>().updateUser(
        userId: widget.userId,
        fullName: newFullName,
        role: newRole,
        status: _status,
        originalFullName: oldFullName,
        originalRole: oldRole,
        email: _originalEmail,
        phoneNumber: _phoneController.text,
        nim: _nimController.text,
        studyProgram: _programController.text,
        semester: int.tryParse(_semesterController.text),
        nip: _nipController.text,
        nidn: _nidnController.text,
        originalProfile: _originalProfile,
      );

      /// Memperbarui snapshot lokal.
      ///
      /// Berguna jika suatu saat halaman tidak langsung ditutup
      /// setelah penyimpanan.
      _originalFullName = newFullName;
      _originalRole = newRole;
      if (!mounted) return;
      context.pop('updated');
    } on UserManagementException catch (error) {
      if (!mounted) return;
      _showMessage(
        error.message,
        type: LabFlowNotificationType.warning,
        title: 'Perubahan tidak dapat disimpan',
      );
    } catch (_) {
      if (!mounted) return;
      _showMessage(
        'Gagal memperbarui pengguna.',
        type: LabFlowNotificationType.error,
        title: 'Terjadi kesalahan',
      );
    }
  }

  /// Mengubah status pengguna:
  ///
  /// active    -> suspended
  /// suspended -> active
  ///
  /// Perubahan status memiliki Activity Log sendiri.
  Future<void> _toggleStatus() async {
    if (_isSaving || _isChangingStatus) {
      return;
    }

    /// Nilai ini membaca kondisi SEBELUM operasi.
    ///
    /// Jika saat ini active, berarti aksi berikutnya adalah suspend.
    final suspending = _status == 'active';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFFF6F9EF),
          title: Text(
            suspending ? 'Nonaktifkan Akun?' : 'Aktifkan Akun?',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Text(
            suspending
                ? 'Pengguna tidak akan dapat masuk ke LabFlow sampai akun diaktifkan kembali.'
                : 'Pengguna akan kembali dapat masuk ke LabFlow.',
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
                backgroundColor: suspending
                    ? const Color(0xFFBD3232)
                    : const Color(0xFF111111),
                foregroundColor: Colors.white,
              ),
              child: Text(suspending ? 'Nonaktifkan' : 'Aktifkan'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final actionCubit = context.read<UserManagementActionCubit>();
    try {
      await actionCubit.setUserStatus(
        userId: widget.userId,
        fullName: _originalFullName,
        email: _originalEmail,
        suspend: suspending,
      );
      _status = suspending ? 'suspended' : 'active';
      if (!mounted) return;
      context.pop(suspending ? 'suspended' : 'activated');
    } on UserManagementException catch (error) {
      if (!mounted) return;
      _showMessage(
        error.message,
        type: LabFlowNotificationType.warning,
        title: 'Status tidak dapat diubah',
      );
    } catch (_) {
      if (!mounted) return;
      _showMessage(
        'Gagal mengubah status pengguna.',
        type: LabFlowNotificationType.error,
        title: 'Perubahan status gagal',
      );
    }
  }

    void _showPasswordResetHelp() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Prosedur Reset Password'),
        content: Text(
          'Pada Firebase Spark Plan, reset password diproses langsung oleh pengelola ' 
          'melalui Firebase Authentication Console -> Tab Users -> Kirim Email Reset Password ' 
          'ke alamat terdaftar ().\n\n' 
          'Langkah ini menjamin keamanan kredensial tanpa membocorkan password baru kepada siapapun.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Mengerti'),
          ),
        ],
      ),
    );
  }

  void _showMessage(
    String message, {
    LabFlowNotificationType type = LabFlowNotificationType.error,
    String? title,
  }) {
    showLabFlowNotification(
      context: context,
      message: message,
      type: type,
      title: title,
    );
  }

  /// Validasi nama pengguna.
  String? _validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) {
      return 'Nama lengkap wajib diisi.';
    }
    if (name.length < 3) {
      return 'Nama lengkap terlalu pendek.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UserManagementActionCubit, bool>(
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F9EF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F9EF),
        elevation: 0,
        title: const Text(
          'Edit Pengguna',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: BlocBuilder<UserDetailCubit, UserDetailState>(
        builder: (context, state) {
          if (state is UserDetailLoading) {
            return const LabFlowLoadingState(
              title: 'Memuat pengguna',
              message: 'Mengambil data pengguna yang dipilih.',
            );
          }
          if (state is UserDetailFailure) {
            return const LabFlowConnectionErrorState(
              title: 'Pengguna tidak dapat dimuat',
              message:
                  'Data pengguna tidak dapat diambil saat ini. '
                  'Periksa koneksi Anda lalu coba lagi.',
            );
          }
          final profile = (state as UserDetailLoaded).profile;
          _fillForm(profile);
          return _buildForm(profile);
        },
      ),
    );
  }

  Widget _buildForm(UserProfile profile) {
    /// Akun Superadmin utama dilindungi.
    ///
    /// User Management tidak boleh digunakan untuk
    /// mengubah role, status, ataupun nama Superadmin utama.
    final isSuperadmin = profile.role == 'superadmin';
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Perbarui Pengguna',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111111),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Kelola data profil, role, dan status akun pengguna LabFlow.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 24),

              /// =================================================
              /// NAMA
              /// =================================================
              TextFormField(
                controller: _nameController,
                onChanged: (_) => setState(() {}),
                enabled: !isSuperadmin,
                validator: _validateName,
                textInputAction: TextInputAction.next,
                decoration: _inputDecoration(
                  'Nama Lengkap',
                  Icons.person_outline_rounded,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                onChanged: (_) => setState(() {}),
                maxLength: 20,
                keyboardType: TextInputType.phone,
                decoration: _inputDecoration('Nomor HP', Icons.phone_outlined),
              ),
              if (_role == 'student') ...[
                TextFormField(
                  controller: _nimController,
                  onChanged: (_) => setState(() {}),
                  maxLength: 30,
                  decoration: _inputDecoration('NIM', Icons.badge_outlined),
                ),
                TextFormField(
                  controller: _programController,
                  onChanged: (_) => setState(() {}),
                  maxLength: 100,
                  decoration: _inputDecoration(
                    'Program Studi',
                    Icons.school_outlined,
                  ),
                ),
                TextFormField(
                  controller: _semesterController,
                  onChanged: (_) => setState(() {}),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final raw = value?.trim() ?? '';
                    if (raw.isEmpty) return null;
                    final semester = int.tryParse(raw);
                    return semester == null || semester < 1 || semester > 14
                        ? 'Semester harus 1–14.'
                        : null;
                  },
                  decoration: _inputDecoration(
                    'Semester (1–14)',
                    Icons.calendar_month_outlined,
                  ),
                ),
              ],
              if (_role == 'lab_admin') ...[
                TextFormField(
                  controller: _nipController,
                  onChanged: (_) => setState(() {}),
                  maxLength: 30,
                  decoration: _inputDecoration('NIP', Icons.badge_outlined),
                ),
                TextFormField(
                  controller: _nidnController,
                  onChanged: (_) => setState(() {}),
                  maxLength: 30,
                  decoration: _inputDecoration('NIDN', Icons.school_outlined),
                ),
              ],
              const SizedBox(height: 16),

              /// =================================================
              /// EMAIL
              /// =================================================
              TextFormField(
                controller: _emailController,
                readOnly: true,
                keyboardType: TextInputType.emailAddress,
                validator: AuthValidator.validateEmail,
                decoration: _inputDecoration('Email (Dikelola via Permohonan User)', Icons.email_outlined),
              ),
              const SizedBox(height: 6),
              const Text(
                'Perubahan email diajukan langsung oleh pemilik akun melalui menu Keamanan Akun dan disetujui Superadmin pada menu Permohonan Ubah Email.',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
              if (profile.hasPendingEmailChange) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFF59E0B)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Color(0xFFB45309), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Perubahan email tertunda: ${profile.pendingEmail} (Menunggu verifikasi link)',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _showPasswordResetHelp,
                icon: const Icon(Icons.lock_reset_rounded),
                label: const Text('Petunjuk Reset Password'),
              ),
              const SizedBox(height: 16),

              /// =================================================
              /// ROLE
              /// =================================================
              DropdownButtonFormField<String>(
                initialValue: isSuperadmin ? 'superadmin' : _role,
                decoration: _inputDecoration(
                  'Role',
                  Icons.admin_panel_settings_outlined,
                ),
                items: isSuperadmin
                    ? const [
                        DropdownMenuItem(
                          value: 'superadmin',
                          child: Text('Superadmin'),
                        ),
                      ]
                    : const [
                        DropdownMenuItem(
                          value: 'student',
                          child: Text('Student'),
                        ),
                        DropdownMenuItem(
                          value: 'lab_admin',
                          child: Text('Lab Admin'),
                        ),
                      ],
                onChanged: isSuperadmin
                    ? null
                    : (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _role = value;
                        });
                      },
              ),
              const SizedBox(height: 16),

              /// =================================================
              /// STATUS
              /// =================================================
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFD8DDD0)),
                ),
                child: Row(
                  children: [
                    Icon(
                      _status == 'active'
                          ? Icons.check_circle_outline_rounded
                          : Icons.block_outlined,
                      color: _status == 'active'
                          ? const Color(0xFF188A55)
                          : const Color(0xFFBD3232),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Status Akun',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _status == 'active' ? 'Aktif' : 'Suspended',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _status == 'active'
                            ? const Color(0xFFE5F6EC)
                            : const Color(0xFFFFE8E8),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _status == 'active' ? 'Active' : 'Suspended',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _status == 'active'
                              ? const Color(0xFF188A55)
                              : const Color(0xFFBD3232),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!isSuperadmin) ...[
                const SizedBox(height: 28),

                /// ===============================================
                /// SIMPAN
                /// ===============================================
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _isSaving || _isChangingStatus || !_isDirty
                        ? null
                        : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF111111),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF444444),
                      shape: const StadiumBorder(),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.save_outlined, size: 20),
                              SizedBox(width: 10),
                              Text(
                                'Simpan Perubahan',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                  ),
                ),
                if (!_isDirty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Center(
                      child: Text(
                        'Belum ada perubahan untuk disimpan.',
                        style: TextStyle(color: Color(0xFF6B7280)),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),

                /// ===============================================
                /// ACTIVE / SUSPEND
                /// ===============================================
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _isSaving || _isChangingStatus
                        ? null
                        : _toggleStatus,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _status == 'active'
                          ? const Color(0xFFBD3232)
                          : const Color(0xFF188A55),
                      side: BorderSide(
                        color: _status == 'active'
                            ? const Color(0xFFE8C8C8)
                            : const Color(0xFFC7E7D5),
                      ),
                      shape: const StadiumBorder(),
                    ),
                    icon: Icon(
                      _status == 'active'
                          ? Icons.block_outlined
                          : Icons.check_circle_outline,
                    ),
                    label: Text(
                      _isChangingStatus
                          ? 'Memproses...'
                          : _status == 'active'
                          ? 'Nonaktifkan Akun'
                          : 'Aktifkan Akun',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
              if (isSuperadmin) ...[
                const SizedBox(height: 24),
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
                      Icon(Icons.shield_outlined, color: Color(0xFF111111)),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Akun Superadmin utama dilindungi dan tidak dapat diubah melalui User Management.',
                          style: TextStyle(
                            color: Color(0xFF111111),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Style dasar input form.
  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD8DDD0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF111111), width: 1.4),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD8DDD0)),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFBD3232)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFBD3232), width: 1.4),
      ),
    );
  }
}
