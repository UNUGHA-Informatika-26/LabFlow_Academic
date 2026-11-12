import 'package:flutter/material.dart';

import '../../../core/offline/admin_entity_draft_store.dart';
import '../../../core/offline/conflict_resolution.dart';

/// Menampilkan badge status untuk draft offline (`pending`, `conflict`, `syncing`, `failed`).
class LabFlowDraftStatusBadge extends StatelessWidget {
  const LabFlowDraftStatusBadge({required this.status, super.key});

  final DraftSyncStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, bgColor, fgColor, icon) = switch (status) {
      DraftSyncStatus.pending => (
        'Menunggu Sinkronisasi',
        const Color(0xFFFFF4D6),
        const Color(0xFF9A6700),
        Icons.schedule_rounded,
      ),
      DraftSyncStatus.conflict => (
        'Konflik Data',
        const Color(0xFFFFE4E4),
        const Color(0xFFB42318),
        Icons.warning_amber_rounded,
      ),
      DraftSyncStatus.syncing => (
        'Menyinkronkan...',
        const Color(0xFFE8EEFF),
        const Color(0xFF1D4ED8),
        Icons.sync_rounded,
      ),
      DraftSyncStatus.failed => (
        'Gagal Sinkronisasi',
        const Color(0xFFFFE4E4),
        const Color(0xFFB42318),
        Icons.error_outline_rounded,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fgColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fgColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Panel daftar draft offline yang belum disinkronkan.
class LabFlowOfflineDraftsPanel extends StatelessWidget {
  const LabFlowOfflineDraftsPanel({
    required this.drafts,
    required this.isOnline,
    required this.titleBuilder,
    required this.subtitleBuilder,
    required this.onResumeEdit,
    required this.onSyncDraft,
    required this.onDeleteDraft,
    super.key,
  });

  final List<OfflineEntityDraft> drafts;
  final bool isOnline;
  final String Function(OfflineEntityDraft draft) titleBuilder;
  final String Function(OfflineEntityDraft draft) subtitleBuilder;
  final void Function(OfflineEntityDraft draft) onResumeEdit;
  final void Function(OfflineEntityDraft draft) onSyncDraft;
  final void Function(OfflineEntityDraft draft) onDeleteDraft;

  @override
  Widget build(BuildContext context) {
    if (drafts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFDDE2D5), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: Color(0xFFEAFBCB),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.cloud_upload_outlined,
                  size: 18,
                  color: Color(0xFF111111),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Draft Lokal Belum Disinkronkan (${drafts.length})',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111111),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isOnline
                          ? 'Koneksi tersedia. Pilih Sinkronkan untuk mengirim draft secara manual.'
                          : 'Perangkat sedang offline. Draft tersimpan aman di perangkat Anda.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < drafts.length; i++) ...[
            if (i > 0) const Divider(height: 20, color: Color(0xFFE5E7EB)),
            _buildDraftItem(drafts[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildDraftItem(OfflineEntityDraft draft) {
    final isSyncing = draft.syncStatus == DraftSyncStatus.syncing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titleBuilder(draft),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111111),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitleBuilder(draft),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            LabFlowDraftStatusBadge(status: draft.syncStatus),
          ],
        ),
        if (draft.lastError != null && draft.lastError!.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF5F5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              draft.lastError!,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFB42318),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: isSyncing ? null : () => onResumeEdit(draft),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Lanjutkan Edit'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: const Color(0xFF111111),
                side: const BorderSide(color: Color(0xFFD8DDD0)),
              ),
            ),
            FilledButton.icon(
              onPressed: (!isOnline || isSyncing)
                  ? null
                  : () => onSyncDraft(draft),
              icon: isSyncing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.sync_rounded, size: 16),
              label: Text(
                draft.syncStatus == DraftSyncStatus.conflict
                    ? 'Selesaikan Konflik'
                    : 'Sinkronkan',
              ),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                backgroundColor: const Color(0xFF111111),
                foregroundColor: Colors.white,
              ),
            ),
            TextButton.icon(
              onPressed: isSyncing ? null : () => onDeleteDraft(draft),
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              label: const Text('Hapus Draft'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: const Color(0xFFBD3232),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Dialog interaktif untuk menyelesaikan konflik perubahan data (Case 2).
///
/// Pengguna dapat memilih untuk setiap field yang berkonflik:
/// - Gunakan Nilai Lokal
/// - Gunakan Nilai Server
/// - Sesuaikan Nilai Secara Manual
Future<Map<String, ConflictResolutionDecision>?>
showLabFlowConflictResolutionDialog({
  required BuildContext context,
  required ConflictAnalysis analysis,
  required Map<String, String> fieldLabels,
  String title = 'Konflik Perubahan Data Terdeteksi',
}) {
  return showDialog<Map<String, ConflictResolutionDecision>>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _LabFlowConflictResolutionDialog(
      analysis: analysis,
      fieldLabels: fieldLabels,
      title: title,
    ),
  );
}

class _LabFlowConflictResolutionDialog extends StatefulWidget {
  const _LabFlowConflictResolutionDialog({
    required this.analysis,
    required this.fieldLabels,
    required this.title,
  });

  final ConflictAnalysis analysis;
  final Map<String, String> fieldLabels;
  final String title;

  @override
  State<_LabFlowConflictResolutionDialog> createState() =>
      _LabFlowConflictResolutionDialogState();
}

class _LabFlowConflictResolutionDialogState
    extends State<_LabFlowConflictResolutionDialog> {
  late final Map<String, ConflictResolutionChoice> _choices;
  late final Map<String, TextEditingController> _manualControllers;

  @override
  void initState() {
    super.initState();
    _choices = <String, ConflictResolutionChoice>{};
    _manualControllers = <String, TextEditingController>{};
    for (final entry in widget.analysis.conflicts.entries) {
      _choices[entry.key] = ConflictResolutionChoice.useLocal;
      _manualControllers[entry.key] = TextEditingController(
        text: '${entry.value.localValue ?? ''}',
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _manualControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _confirm() {
    final decisions = <String, ConflictResolutionDecision>{};
    for (final entry in widget.analysis.conflicts.entries) {
      final field = entry.key;
      final conflict = entry.value;
      final choice = _choices[field] ?? ConflictResolutionChoice.useLocal;
      if (choice == ConflictResolutionChoice.useLocal) {
        decisions[field] = ConflictResolutionDecision.useLocal(
          expectedServerValue: conflict.serverValue,
          hasExpectedServerValue: true,
        );
      } else if (choice == ConflictResolutionChoice.useServer) {
        decisions[field] = ConflictResolutionDecision.useServer(
          expectedServerValue: conflict.serverValue,
          hasExpectedServerValue: true,
        );
      } else {
        final rawText = _manualControllers[field]?.text.trim() ?? '';
        final Object? manualVal = conflict.localValue is int
            ? (int.tryParse(rawText) ?? conflict.localValue)
            : rawText;
        decisions[field] = ConflictResolutionDecision.manual(
          manualVal,
          expectedServerValue: conflict.serverValue,
          hasExpectedServerValue: true,
        );
      }
    }
    Navigator.of(context).pop(decisions);
  }

  @override
  Widget build(BuildContext context) {
    final conflicts = widget.analysis.conflicts.values.toList();

    return AlertDialog(
      backgroundColor: const Color(0xFFF6F9EF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFB42318),
            size: 26,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111111),
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Data di server telah diubah oleh pengguna lain sejak draft ini dibuat. '
                'Pilih nilai yang ingin digunakan untuk setiap field yang berkonflik:',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Color(0xFF4B5563),
                ),
              ),
              const SizedBox(height: 16),
              for (final conflict in conflicts) ...[
                _buildConflictCard(conflict),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _confirm,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF111111),
            foregroundColor: Colors.white,
          ),
          child: const Text('Terapkan & Simpan'),
        ),
      ],
    );
  }

  Widget _buildConflictCard(FieldConflict conflict) {
    final label = widget.fieldLabels[conflict.field] ?? conflict.field;
    final selectedChoice =
        _choices[conflict.field] ?? ConflictResolutionChoice.useLocal;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE2D5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111111),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Nilai awal (Baseline): ${conflict.baselineValue ?? "-"}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 8),
          RadioGroup<ConflictResolutionChoice>(
            groupValue: selectedChoice,
            onChanged: (value) {
              if (value != null) {
                setState(() => _choices[conflict.field] = value);
              }
            },
            child: Column(
              children: [
                RadioListTile<ConflictResolutionChoice>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: ConflictResolutionChoice.useLocal,
                  title: Text(
                    'Gunakan nilai lokal: "${conflict.localValue ?? ""}"',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                RadioListTile<ConflictResolutionChoice>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: ConflictResolutionChoice.useServer,
                  title: Text(
                    'Gunakan nilai server: "${conflict.serverValue ?? ""}"',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                RadioListTile<ConflictResolutionChoice>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: ConflictResolutionChoice.manual,
                  title: const Text(
                    'Sesuaikan secara manual',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          if (selectedChoice == ConflictResolutionChoice.manual) ...[
            const SizedBox(height: 6),
            TextField(
              controller: _manualControllers[conflict.field],
              decoration: InputDecoration(
                labelText: 'Nilai manual untuk $label',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
