import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/presentation/navigation/labflow_back_fallback.dart';
import '../../../../shared/presentation/notifications/labflow_notification.dart';
import '../cubit/change_password_cubit.dart';
import '../cubit/change_password_state.dart';
import '../../data/auth_service.dart';

class AccountSecurityPage extends StatelessWidget {
  const AccountSecurityPage({required this.returnPath, super.key});

  final String returnPath;

  @override
  Widget build(BuildContext context) => _SecurityScaffold(
    returnPath: returnPath,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        const Text(
          'Kelola keamanan akun Firebase Anda.',
          style: TextStyle(fontSize: 15, color: Color(0xFF6B7280)),
        ),
        const SizedBox(height: 22),
        _SecurityTile(
          icon: Icons.lock_reset_rounded,
          title: 'Ganti Password',
          subtitle: 'Verifikasi password saat ini sebelum mengubahnya.',
          onTap: () =>
              context.push('${_securityPath(returnPath)}/change-password'),
        ),
        const SizedBox(height: 14),
        _SecurityTile(
          icon: Icons.alternate_email_rounded,
          title: 'Ubah Email Akun',
          subtitle: 'Ajukan permohonan perubahan email melalui persetujuan Superadmin.',
          onTap: () =>
              context.push('${_securityPath(returnPath)}/change-email'),
        ),
      ],
    ),
  );
}

String _securityPath(String returnPath) => switch (returnPath) {
  '/student/profile' => '/student/profile/security',
  '/lab-admin/profile' => '/lab-admin/profile/security',
  '/superadmin/profile' => '/superadmin/profile/security',
  _ => '/profile/security',
};

class ChangePasswordPage extends StatelessWidget {
  const ChangePasswordPage({this.authService, super.key});

  final AuthService? authService;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => ChangePasswordCubit(authService ?? AuthService()),
    child: const _ChangePasswordView(),
  );
}

class _ChangePasswordView extends StatefulWidget {
  const _ChangePasswordView();

  @override
  State<_ChangePasswordView> createState() => _ChangePasswordViewState();
}

class _ChangePasswordViewState extends State<_ChangePasswordView> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    context.read<ChangePasswordCubit>().submit(
      currentPassword: _currentController.text,
      newPassword: _newController.text,
      confirmation: _confirmController.text,
    );
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<ChangePasswordCubit, ChangePasswordState>(
        listener: (context, state) {
          switch (state) {
            case ChangePasswordSuccess():
              _currentController.clear();
              _newController.clear();
              _confirmController.clear();
              showLabFlowNotification(
                context: context,
                title: 'Password berhasil diubah',
                message: 'Gunakan password baru pada login berikutnya.',
                type: LabFlowNotificationType.success,
              );
            case ChangePasswordFailure(:final message):
              showLabFlowNotification(
                context: context,
                title: 'Password belum diubah',
                message: message,
                type: LabFlowNotificationType.error,
              );
            default:
              break;
          }
        },
        builder: (context, state) {
          final isLoading = state is ChangePasswordLoading;
          return _SecurityScaffold(
            title: 'Ganti Password',
            returnPath: _securityParentPath(context),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  const Text(
                    'Masukkan password saat ini untuk memverifikasi akun Anda.',
                    style: TextStyle(fontSize: 15, color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(height: 22),
                  _PasswordField(
                    controller: _currentController,
                    label: 'Password saat ini',
                    obscureText: _obscureCurrent,
                    enabled: !isLoading,
                    onToggle: () =>
                        setState(() => _obscureCurrent = !_obscureCurrent),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Password saat ini wajib diisi.'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  _PasswordField(
                    controller: _newController,
                    label: 'Password baru',
                    obscureText: _obscureNew,
                    enabled: !isLoading,
                    onToggle: () => setState(() => _obscureNew = !_obscureNew),
                    validator: (value) => _passwordValidator(value),
                  ),
                  const SizedBox(height: 14),
                  _PasswordField(
                    controller: _confirmController,
                    label: 'Konfirmasi password baru',
                    obscureText: _obscureConfirm,
                    enabled: !isLoading,
                    onToggle: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Konfirmasi password wajib diisi.';
                      }
                      if (value != _newController.text) {
                        return 'Konfirmasi password tidak sama.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 54,
                    child: FilledButton(
                      onPressed: isLoading ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF111111),
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder(),
                      ),
                      child: isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Ganti Password',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

  String? _passwordValidator(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password wajib diisi.';
    }
    if (value.length < 8) {
      return 'Password minimal 8 karakter.';
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Password harus mengandung angka.';
    }
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=]').hasMatch(value)) {
      return 'Password harus mengandung simbol.';
    }
    return null;
  }

  String _securityParentPath(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    return path.replaceFirst(RegExp(r'/change-password$'), '');
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.obscureText,
    required this.enabled,
    required this.onToggle,
    required this.validator,
  });

  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final bool enabled;
  final VoidCallback onToggle;
  final String? Function(String?) validator;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    obscureText: obscureText,
    enabled: enabled,
    validator: validator,
    autofillHints: const [AutofillHints.password],
    decoration: InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      suffixIcon: IconButton(
        tooltip: obscureText ? 'Tampilkan password' : 'Sembunyikan password',
        onPressed: onToggle,
        icon: Icon(
          obscureText
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
        ),
      ),
    ),
  );
}

class _SecurityScaffold extends StatelessWidget {
  const _SecurityScaffold({
    this.title = 'Keamanan Akun',
    required this.returnPath,
    required this.child,
  });

  final String title;
  final String returnPath;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF6F9EF),
    appBar: AppBar(
      backgroundColor: const Color(0xFFF6F9EF),
      title: Text(
        title,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
      ),
      leading: IconButton(
        tooltip: 'Kembali',
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => popOrGo(context, returnPath),
      ),
    ),
    body: SafeArea(child: child),
  );
}

class _SecurityTile extends StatelessWidget {
  const _SecurityTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE2D5)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 25),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    ),
  );
}
