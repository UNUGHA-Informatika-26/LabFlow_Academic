import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/presentation/notifications/labflow_notification.dart';
import '../../data/auth_service.dart';

class ForgotPasswordPage extends StatelessWidget {
  const ForgotPasswordPage({this.authService, super.key});

  final AuthService? authService;

  static const String requestTemplate =
      "Assalamu'alaikum, saya membutuhkan bantuan untuk pemulihan akun LabFlow.\n\n"
      'Nama: [Nama lengkap]\n'
      'Role: [Student/Lab Admin]\n'
      'Email akun: [Email terdaftar]\n'
      'NIM/NIP: [Identitas pengguna]\n'
      'Kendala: Saya tidak dapat mengakses akun karena lupa password.\n\n'
      'Mohon bantuan untuk melakukan reset akses akun. Terima kasih.';

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF6F9EF),
    appBar: AppBar(
      backgroundColor: const Color(0xFFF6F9EF),
      title: const Text(
        'Bantuan Akses Akun',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
      ),
      leading: IconButton(
        onPressed: () => context.pop(),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.support_agent_rounded,
                    size: 40,
                    color: Color(0xFF1B4332),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Prosedur Pemulihan Terkelola',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF111827),
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Tidak dapat mengakses akun LabFlow? Hubungi Superadmin untuk mendapatkan bantuan pemulihan akun. Identitas pemohon akan diverifikasi sebelum proses perubahan kredensial dilakukan.',
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.45,
                            color: Color(0xFF4B5563),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Template Permohonan Bantuan',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Salin format di bawah ini dan kirimkan melalui saluran komunikasi resmi Superadmin / Pengelola Laboratorium:',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFD1D5DB)),
              ),
              child: const SelectableText(
                requestTemplate,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.5,
                  color: Color(0xFF1F2937),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    const ClipboardData(text: requestTemplate),
                  );
                  if (context.mounted) {
                    showLabFlowNotification(
                      context: context,
                      title: 'Tersalin',
                      message: 'Template permohonan telah disalin ke clipboard.',
                      type: LabFlowNotificationType.success,
                    );
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 20),
                label: const Text(
                  'Salin Template',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1B4332),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 50,
              child: OutlinedButton(
                onPressed: () => context.pop(),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFD1D5DB)),
                  foregroundColor: const Color(0xFF374151),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Kembali ke Login',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
