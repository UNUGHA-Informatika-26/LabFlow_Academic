import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/superadmin_whatsapp_config.dart';
import '../../../../core/validators/auth_validator.dart';
import '../../../../shared/presentation/notifications/labflow_notification.dart';
import '../../../../shared/presentation/states/labflow_suspended_account_state.dart';
import '../../data/auth_service.dart';
import '../cubit/login_cubit.dart';
import '../cubit/login_state.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider<AuthService>(
      create: (_) => AuthService(),
      child: BlocProvider(
        create: (context) => LoginCubit(context.read<AuthService>()),
        child: const _LoginView(),
      ),
    );
  }
}

class _LoginView extends StatefulWidget {
  const _LoginView();

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // Visibilitas password hanya memengaruhi tampilan field login.
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Memvalidasi form sebelum menyerahkan autentikasi ke Cubit.
  void _login() {
    FocusScope.of(context).unfocus();

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    context.read<LoginCubit>().login(
      email: _emailController.text,
      password: _passwordController.text,
    );
  }

  /// Membuka WhatsApp Superadmin bagi mahasiswa
  /// yang belum memiliki akun LabFlow.
  Future<void> _contactAdmin() async {
    final superadminNumber = SuperadminWhatsAppConfig.instance.number;

    if (superadminNumber == null) {
      if (!mounted) {
        return;
      }

      _showNotification(
        'Kontak WhatsApp Superadmin belum dikonfigurasi.',
        title: 'Konfigurasi belum lengkap',
        type: LabFlowNotificationType.warning,
      );

      return;
    }

    const message =
        'Halo Superadmin, saya ingin meminta bantuan terkait akun LabFlow. '
        'Saat ini saya belum memiliki akun untuk mengakses aplikasi.';

    final uri = Uri.https('wa.me', '/$superadminNumber', {'text': message});

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!opened && mounted) {
      _showNotification(
        'WhatsApp tidak dapat dibuka pada perangkat ini.',
        title: 'WhatsApp tidak dapat dibuka',
        type: LabFlowNotificationType.error,
      );
    }
  }

  void _showNotification(
    String message, {
    required String title,
    required LabFlowNotificationType type,
  }) {
    showLabFlowNotification(
      context: context,
      title: title,
      message: message,
      type: type,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<LoginCubit, LoginState>(
      listener: _handleLoginState,
      builder: (context, state) => _buildPage(state),
    );
  }

  void _handleLoginState(BuildContext context, LoginState state) {
    switch (state) {
      case LoginFailure(isAccountSuspended: true):
        break;
      case LoginFailure(:final message, :final isUnexpected):
        _showNotification(
          message,
          title: 'Login gagal',
          type: isUnexpected
              ? LabFlowNotificationType.error
              : LabFlowNotificationType.warning,
        );
      case LoginSuccess(:final profile):
        switch (profile.role) {
          case 'superadmin':
            context.go('/superadmin');
          case 'lab_admin':
            context.go('/lab-admin');
          case 'student':
            context.go('/student');
          default:
            _rejectUnknownRole(context);
        }
      default:
        break;
    }
  }

  Future<void> _rejectUnknownRole(BuildContext context) async {
    await context.read<AuthService>().signOut();
    if (!context.mounted) return;

    context.read<LoginCubit>().reset();
    _showNotification(
      'Role akun tidak dikenali.',
      title: 'Akses ditolak',
      type: LabFlowNotificationType.warning,
    );
  }

  void _returnToLogin() {
    FocusScope.of(context).unfocus();
    _passwordController.clear();
    context.read<LoginCubit>().reset();
  }

  Widget _buildPage(LoginState state) {
    if (state is LoginFailure && state.isAccountSuspended) {
      return Scaffold(
        backgroundColor: const Color(0xFFF6F9EF),
        body: SafeArea(
          child: LabFlowSuspendedAccountState(
            actionLabel: 'Kembali ke Login',
            onAction: _returnToLogin,
          ),
        ),
      );
    }

    final isLoading = state is LoginLoading;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F9EF),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 32,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 20),
                    _buildIllustration(),
                    const SizedBox(height: 20),
                    const Text(
                      'Selamat Datang',
                      style: TextStyle(
                        fontSize: 36,
                        height: 1.05,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111111),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Masuk untuk mengakses layanan\nlaboratorium.',
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.45,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          _buildEmailField(isLoading),
                          const SizedBox(height: 16),
                          _buildPasswordField(isLoading),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildLoginButton(isLoading),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: isLoading
                            ? null
                            : () => context.push('/forgot-password'),
                        child: const Text('Lupa password?'),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _buildContactAdmin(isLoading),
                    const SizedBox(height: 20),
                    const Center(
                      child: Text(
                        'LabFlow Academic Project',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return const SizedBox(
      height: 31,
      child: Row(
        children: [
          Text(
            'LabFlow.',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111111),
            ),
          ),
          Spacer(),
          Icon(Icons.science_outlined, size: 26, color: Color(0xFF111111)),
        ],
      ),
    );
  }

  Widget _buildIllustration() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: AspectRatio(
        aspectRatio: 350 / 224,
        child: Image.asset(
          'assets/images/auth/login_illustration.png',
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildEmailField(bool isLoading) {
    return TextFormField(
      controller: _emailController,
      enabled: !isLoading,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      textCapitalization: TextCapitalization.none,
      autocorrect: false,
      enableSuggestions: false,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: AuthValidator.validateEmail,
      decoration: _inputDecoration(
        label: 'Email',
        hint: 'mahasiswa@example.com',
        suffixIcon: const Icon(Icons.email_outlined, color: Color(0xFF111111)),
      ),
    );
  }

  Widget _buildPasswordField(bool isLoading) {
    return TextFormField(
      controller: _passwordController,
      enabled: !isLoading,
      obscureText: _obscurePassword,
      textInputAction: TextInputAction.done,
      autocorrect: false,
      enableSuggestions: false,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: AuthValidator.validatePassword,
      onFieldSubmitted: isLoading
          ? null
          : (_) {
              _login();
            },
      decoration: _inputDecoration(
        label: 'Password',
        hint: '••••••••',
        suffixIcon: IconButton(
          tooltip: _obscurePassword
              ? 'Tampilkan password'
              : 'Sembunyikan password',
          onPressed: isLoading
              ? null
              : () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: const Color(0xFF111111),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required Widget suffixIcon,
  }) {
    const normalBorderColor = Color(0xFFD8DDD0);
    const darkColor = Color(0xFF111111);
    const errorColor = Color(0xFFBD3232);

    return InputDecoration(
      labelText: label,
      hintText: hint,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      labelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Color(0xFF6B7280),
      ),
      hintStyle: const TextStyle(fontSize: 15, color: darkColor),
      errorStyle: const TextStyle(fontSize: 12, color: errorColor),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: normalBorderColor),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: normalBorderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: darkColor, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: errorColor),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: errorColor, width: 1.4),
      ),
    );
  }

  Widget _buildLoginButton(bool isLoading) {
    return SizedBox(
      width: double.infinity,
      height: 53,
      child: FilledButton(
        onPressed: isLoading ? null : _login,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF111111),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF111111),
          disabledForegroundColor: Colors.white,
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
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.arrow_forward_rounded, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'Masuk',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildContactAdmin(bool isLoading) {
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          const Text(
            'Belum memiliki akun?',
            style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
          ),
          TextButton(
            onPressed: isLoading ? null : _contactAdmin,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Hubungi Superadmin',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111111),
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
