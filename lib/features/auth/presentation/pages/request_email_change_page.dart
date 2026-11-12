import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/presentation/notifications/labflow_notification.dart';
import '../../data/email_change_service.dart';
import '../../domain/email_change_request.dart';
import '../../../../core/validators/auth_validator.dart';

class RequestEmailChangePage extends StatefulWidget {
  const RequestEmailChangePage({
    this.emailChangeService,
    this.firebaseAuth,
    super.key,
  });

  final EmailChangeService? emailChangeService;
  final FirebaseAuth? firebaseAuth;

  @override
  State<RequestEmailChangePage> createState() => _RequestEmailChangePageState();
}

class _RequestEmailChangePageState extends State<RequestEmailChangePage> {
  late final EmailChangeService _service;
  late final FirebaseAuth _auth;

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _reasonController = TextEditingController();

  bool _isSubmitting = false;
  bool _isActionRunning = false;

  @override
  void initState() {
    super.initState();
    _service = widget.emailChangeService ?? EmailChangeService();
    _auth = widget.firebaseAuth ?? FirebaseAuth.instance;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSubmitting = true);
    try {
      await _service.submitRequest(
        newEmail: _emailController.text,
        reason: _reasonController.text,
      );
      if (!mounted) return;
      _emailController.clear();
      _reasonController.clear();
      showLabFlowNotification(
        context: context,
        title: 'Permohonan Terkirim',
        message: 'Permohonan perubahan email telah diajukan kepada Superadmin.',
        type: LabFlowNotificationType.success,
      );
    } on EmailChangeException catch (e) {
      if (!mounted) return;
      showLabFlowNotification(
        context: context,
        title: 'Gagal Mengajukan',
        message: e.message,
        type: LabFlowNotificationType.error,
      );
    } catch (e) {
      if (!mounted) return;
      showLabFlowNotification(
        context: context,
        title: 'Terjadi Kesalahan',
        message: 'Permohonan tidak dapat dikirim: $e',
        type: LabFlowNotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _sendVerificationLink(EmailChangeRequest request) async {
    setState(() => _isActionRunning = true);
    try {
      await _service.sendVerificationLink(request);
      if (!mounted) return;
      showLabFlowNotification(
        context: context,
        title: 'Tautan Terkirim',
        message:
            'Tautan verifikasi telah dikirim ke ${request.requestedEmail}. Silakan periksa inbox email Anda.',
        type: LabFlowNotificationType.success,
      );
    } on EmailChangeException catch (e) {
      if (!mounted) return;
      showLabFlowNotification(
        context: context,
        title: 'Gagal Mengirim Verifikasi',
        message: e.message,
        type: LabFlowNotificationType.error,
      );
    } catch (e) {
      if (!mounted) return;
      showLabFlowNotification(
        context: context,
        title: 'Terjadi Kesalahan',
        message: 'Tidak dapat mengirim verifikasi: $e',
        type: LabFlowNotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _isActionRunning = false);
    }
  }

  Future<void> _checkAndSync(EmailChangeRequest request) async {
    setState(() => _isActionRunning = true);
    try {
      final success = await _service.checkAndSyncVerifiedEmail(request);
      if (!mounted) return;
      if (success) {
        showLabFlowNotification(
          context: context,
          title: 'Email Berhasil Diperbarui',
          message:
              'Email akun Anda kini telah berhasil diverifikasi dan disinkronkan.',
          type: LabFlowNotificationType.success,
        );
      } else {
        showLabFlowNotification(
          context: context,
          title: 'Belum Terverifikasi',
          message:
              'Email baru belum terverifikasi. Pastikan Anda telah mengklik tautan di email konfirmasi.',
          type: LabFlowNotificationType.warning,
        );
      }
    } on EmailChangeException catch (e) {
      if (!mounted) return;
      showLabFlowNotification(
        context: context,
        title: 'Sinkronisasi Gagal',
        message: e.message,
        type: LabFlowNotificationType.error,
      );
    } catch (e) {
      if (!mounted) return;
      showLabFlowNotification(
        context: context,
        title: 'Terjadi Kesalahan',
        message: 'Gagal menyinkronkan status email: $e',
        type: LabFlowNotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _isActionRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentEmail = _auth.currentUser?.email ?? '-';

    return Scaffold(
      backgroundColor: const Color(0xFFF6F9EF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F9EF),
        title: const Text(
          'Ubah Email Akun',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          tooltip: 'Kembali',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<EmailChangeRequest?>(
          stream: _service.watchMyActiveRequest(),
          builder: (context, snapshot) {
            final activeRequest = snapshot.data;

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                _InfoCard(currentEmail: currentEmail),
                const SizedBox(height: 20),
                if (activeRequest != null) ...[
                  _ActiveRequestCard(
                    request: activeRequest,
                    isRunning: _isActionRunning,
                    onSendLink: () => _sendVerificationLink(activeRequest),
                    onSync: () => _checkAndSync(activeRequest),
                  ),
                  const SizedBox(height: 20),
                ] else ...[
                  _RequestForm(
                    formKey: _formKey,
                    emailController: _emailController,
                    reasonController: _reasonController,
                    isSubmitting: _isSubmitting,
                    onSubmit: _submitRequest,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.currentEmail});
  final String currentEmail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE2D5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.shield_outlined, color: Color(0xFF1B4332), size: 22),
              SizedBox(width: 8),
              Text(
                'Prosedur Perubahan Email',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Perubahan email membutuhkan persetujuan Superadmin demi integritas akademik. '
            'Setelah disetujui, tautan verifikasi akan dikirim ke email baru Anda.',
            style: TextStyle(fontSize: 13, color: Color(0xFF4B5563), height: 1.4),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Text(
                  'Email Aktif: ',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Expanded(
                  child: Text(
                    currentEmail,
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1F2937),
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
}

class _ActiveRequestCard extends StatelessWidget {
  const _ActiveRequestCard({
    required this.request,
    required this.isRunning,
    required this.onSendLink,
    required this.onSync,
  });

  final EmailChangeRequest request;
  final bool isRunning;
  final VoidCallback onSendLink;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final isApproved = request.isApproved;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isApproved ? const Color(0xFFEFF6FF) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isApproved ? const Color(0xFF3B82F6) : const Color(0xFFF59E0B),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isApproved ? Icons.check_circle_outline : Icons.pending_actions_rounded,
                color: isApproved ? const Color(0xFF1D4ED8) : const Color(0xFFB45309),
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                isApproved ? 'Permohonan Disetujui' : 'Menunggu Persetujuan Superadmin',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isApproved ? const Color(0xFF1E40AF) : const Color(0xFF92400E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Email yang diajukan: ${request.requestedEmail}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Alasan: ${request.reason}',
            style: const TextStyle(fontSize: 13, color: Color(0xFF4B5563)),
          ),
          const SizedBox(height: 14),
          if (isApproved) ...[
            const Text(
              'Langkah 1: Klik tombol di bawah untuk mengirim email verifikasi ke alamat baru Anda.\n'
              'Langkah 2: Buka inbox email baru, lalu klik tautan verifikasi.\n'
              'Langkah 3: Kembali ke halaman ini dan tekan "Sinkronkan Email".',
              style: TextStyle(fontSize: 12.5, height: 1.45, color: Color(0xFF1E3A8A)),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isRunning ? null : onSendLink,
                    icon: const Icon(Icons.mark_email_read_outlined, size: 18),
                    label: const Text('Kirim Verifikasi'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: isRunning ? null : onSync,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1B4332),
                    ),
                    icon: const Icon(Icons.sync_rounded, size: 18),
                    label: const Text('Sinkronkan'),
                  ),
                ),
              ],
            ),
          ] else ...[
            const Text(
              'Superadmin sedang memverifikasi identitas dan alasan permohonan Anda. Halaman ini akan otomatis diperbarui setelah disetujui.',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: Color(0xFF78350F)),
            ),
          ],
        ],
      ),
    );
  }
}

class _RequestForm extends StatelessWidget {
  const _RequestForm({
    required this.formKey,
    required this.emailController,
    required this.reasonController,
    required this.isSubmitting,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController reasonController;
  final bool isSubmitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Formulir Permohonan',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            validator: AuthValidator.validateEmail,
            enabled: !isSubmitting,
            decoration: InputDecoration(
              labelText: 'Alamat Email Baru',
              hintText: 'nama@domain.ac.id',
              prefixIcon: const Icon(Icons.alternate_email_rounded),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: reasonController,
            maxLines: 3,
            maxLength: 200,
            enabled: !isSubmitting,
            validator: (v) {
              final raw = v?.trim() ?? '';
              if (raw.length < 5) return 'Alasan minimal 5 karakter.';
              return null;
            },
            decoration: InputDecoration(
              labelText: 'Alasan Perubahan',
              hintText: 'Contoh: Email lama non-aktif / kesalahan penulisan',
              prefixIcon: const Icon(Icons.notes_rounded),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: isSubmitting ? null : onSubmit,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF111111),
                shape: const StadiumBorder(),
              ),
              child: isSubmitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Ajukan Perubahan Email',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
