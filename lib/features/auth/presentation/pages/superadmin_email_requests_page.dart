import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/email_change_service.dart';
import '../../domain/email_change_request.dart';
import '../../../../shared/presentation/notifications/labflow_notification.dart';

class SuperadminEmailRequestsPage extends StatefulWidget {
  const SuperadminEmailRequestsPage({
    this.emailChangeService,
    super.key,
  });

  final EmailChangeService? emailChangeService;

  @override
  State<SuperadminEmailRequestsPage> createState() =>
      _SuperadminEmailRequestsPageState();
}

class _SuperadminEmailRequestsPageState
    extends State<SuperadminEmailRequestsPage> {
  late final EmailChangeService _service;

  @override
  void initState() {
    super.initState();
    _service = widget.emailChangeService ?? EmailChangeService();
  }

  Future<void> _approve(EmailChangeRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Setujui Perubahan Email?'),
        content: Text(
          'Menyetujui perubahan email pengguna ke:\n\n'
          '${request.requestedEmail}\n\n'
          'Pengguna akan diizinkan meminta tautan verifikasi ke email baru.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1B4332),
            ),
            child: const Text('Setujui'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _service.approveRequest(request.id);
      if (!mounted) return;
      showLabFlowNotification(
        context: context,
        title: 'Permohonan Disetujui',
        message: 'Pengguna dapat melanjutkan verifikasi email baru.',
        type: LabFlowNotificationType.success,
      );
    } on EmailChangeException catch (e) {
      if (!mounted) return;
      showLabFlowNotification(
        context: context,
        title: 'Gagal Menyetujui',
        message: e.message,
        type: LabFlowNotificationType.error,
      );
    } catch (e) {
      if (!mounted) return;
      showLabFlowNotification(
        context: context,
        title: 'Terjadi Kesalahan',
        message: 'Tidak dapat memproses approval: $e',
        type: LabFlowNotificationType.error,
      );
    }
  }

  Future<void> _reject(EmailChangeRequest request) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tolak Permohonan?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Menolak permohonan untuk email: ${request.requestedEmail}'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Alasan Penolakan',
                hintText: 'Contoh: Identitas pemohon tidak sesuai',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (reasonController.text.trim().isNotEmpty) {
                Navigator.pop(ctx, true);
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFBD3232),
            ),
            child: const Text('Tolak'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _service.rejectRequest(
        requestId: request.id,
        rejectionReason: reasonController.text,
      );
      if (!mounted) return;
      showLabFlowNotification(
        context: context,
        title: 'Permohonan Ditolak',
        message: 'Permohonan perubahan email telah ditolak.',
        type: LabFlowNotificationType.warning,
      );
    } on EmailChangeException catch (e) {
      if (!mounted) return;
      showLabFlowNotification(
        context: context,
        title: 'Gagal Menolak',
        message: e.message,
        type: LabFlowNotificationType.error,
      );
    } catch (e) {
      if (!mounted) return;
      showLabFlowNotification(
        context: context,
        title: 'Terjadi Kesalahan',
        message: 'Tidak dapat menolak permohonan: $e',
        type: LabFlowNotificationType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F9EF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F9EF),
        title: const Text(
          'Permohonan Ubah Email',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          tooltip: 'Kembali',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: StreamBuilder<List<EmailChangeRequest>>(
        stream: _service.watchAllRequests(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final requests = snapshot.data ?? [];
          if (requests.isEmpty) {
            return const Center(
              child: Text(
                'Tidak ada permohonan perubahan email.',
                style: TextStyle(fontSize: 15, color: Color(0xFF6B7280)),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = requests[index];
              return _RequestItemTile(
                request: item,
                onApprove: () => _approve(item),
                onReject: () => _reject(item),
              );
            },
          );
        },
      ),
    );
  }
}

class _RequestItemTile extends StatelessWidget {
  const _RequestItemTile({
    required this.request,
    required this.onApprove,
    required this.onReject,
  });

  final EmailChangeRequest request;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (request.status) {
      'pending' => const Color(0xFFD97706),
      'approved' => const Color(0xFF2563EB),
      'completed' => const Color(0xFF16A34A),
      'rejected' => const Color(0xFFDC2626),
      _ => const Color(0xFF6B7280),
    };

    final statusLabel = switch (request.status) {
      'pending' => 'Pending Review',
      'approved' => 'Approved (Menunggu Verifikasi User)',
      'completed' => 'Selesai & Tersinkron',
      'rejected' => 'Ditolak',
      _ => request.status,
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'UID: ${request.uid}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.email_outlined, size: 16, color: Color(0xFF4B5563)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${request.currentEmail}  ➔  ${request.requestedEmail}',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Alasan: ${request.reason}',
            style: const TextStyle(fontSize: 13, color: Color(0xFF4B5563)),
          ),
          if (request.rejectionReason != null) ...[
            const SizedBox(height: 4),
            Text(
              'Alasan Penolakan: ${request.rejectionReason}',
              style: const TextStyle(fontSize: 12.5, color: Color(0xFFDC2626)),
            ),
          ],
          if (request.isPending) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                  ),
                  child: const Text('Tolak'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: onApprove,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1B4332),
                  ),
                  child: const Text('Setujui'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
