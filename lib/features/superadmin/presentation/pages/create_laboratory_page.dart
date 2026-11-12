import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/connectivity/connectivity_cubit.dart';
import '../../../../core/offline/admin_entity_draft_store.dart';
import '../../../../shared/presentation/dialogs/labflow_conflict_resolution_dialog.dart';
import '../../../../shared/presentation/notifications/labflow_notification.dart';
import '../../../auth/data/auth_service.dart';
import '../../../laboratory/data/laboratory_service.dart';
import '../../data/activity_log_service.dart';
import '../cubit/laboratory_management_action_cubit.dart';

class CreateLaboratoryPage extends StatelessWidget {
  const CreateLaboratoryPage({this.draftId, super.key});

  final String? draftId;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => LaboratoryManagementActionCubit(
      LaboratoryService(),
      ActivityLogService(),
    ),
    child: _CreateLaboratoryView(draftId: draftId),
  );
}

class _CreateLaboratoryView extends StatefulWidget {
  const _CreateLaboratoryView({this.draftId});

  final String? draftId;

  @override
  State<_CreateLaboratoryView> createState() => _CreateLaboratoryPageState();
}

class _CreateLaboratoryPageState extends State<_CreateLaboratoryView> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();

  final TextEditingController _codeController = TextEditingController();

  final TextEditingController _descriptionController = TextEditingController();

  final TextEditingController _locationController = TextEditingController();

  final AdminEntityDraftStore _draftStore =
      SharedPreferencesAdminEntityDraftStore();
  final AuthService _authService = AuthService();

  String _status = 'active';
  OfflineEntityDraft? _loadedDraft;

  bool get _isLoading => context.read<LaboratoryManagementActionCubit>().state;

  @override
  void initState() {
    super.initState();
    _loadDraftIfPresent();
  }

  Future<void> _loadDraftIfPresent() async {
    final uid = _authService.currentUid;
    if (uid == null) return;
    final targetId =
        widget.draftId ??
        OfflineEntityDraft.createDraftIdFor(
          entityType: DraftEntityType.laboratory,
        );
    final draft = await _draftStore.readDraft(uid, targetId);
    if (draft == null || !mounted) return;
    setState(() {
      _loadedDraft = draft;
      _nameController.text = (draft.data['name'] as String? ?? '');
      _codeController.text = (draft.data['code'] as String? ?? '');
      _locationController.text = (draft.data['location'] as String? ?? '');
      _descriptionController.text =
          (draft.data['description'] as String? ?? '');
      final savedStatus = (draft.data['status'] as String? ?? 'active');
      if (savedStatus == 'active' || savedStatus == 'inactive') {
        _status = savedStatus;
      }
    });
  }

  Future<void> _saveDraftLocally({String? lastError}) async {
    FocusScope.of(context).unfocus();
    final uid = _authService.currentUid;
    if (uid == null) {
      _showMessage(
        'Sesi login tidak ditemukan. Silakan masuk kembali.',
        title: 'Tidak dapat menyimpan draft',
      );
      return;
    }
    final now = DateTime.now().toUtc();
    final draftId =
        _loadedDraft?.draftId ??
        widget.draftId ??
        OfflineEntityDraft.createDraftIdFor(
          entityType: DraftEntityType.laboratory,
        );
    final draft = OfflineEntityDraft(
      draftId: draftId,
      ownerUid: uid,
      entityType: DraftEntityType.laboratory,
      data: <String, Object?>{
        'name': _nameController.text.trim(),
        'code': _codeController.text.trim().toUpperCase(),
        'location': _locationController.text.trim(),
        'description': _descriptionController.text.trim(),
        'status': _status,
      },
      createdAt: _loadedDraft?.createdAt ?? now,
      updatedAt: now,
      syncStatus: lastError == null
          ? DraftSyncStatus.pending
          : DraftSyncStatus.failed,
      lastError: lastError,
    );
    await _draftStore.saveDraft(uid, draft);
    if (!mounted) return;
    setState(() => _loadedDraft = draft);
    _showMessage(
      'Draft laboratorium tersimpan secara lokal. Anda dapat menyinkronkannya secara manual saat online.',
      type: LabFlowNotificationType.info,
      title: 'Draft lokal disimpan',
    );
  }

  Future<void> _deleteLocalDraft() async {
    final uid = _authService.currentUid;
    final draft = _loadedDraft;
    if (uid == null || draft == null) return;
    await _draftStore.removeDraft(uid, draft.draftId);
    if (!mounted) return;
    setState(() => _loadedDraft = null);
    _showMessage(
      'Draft lokal laboratorium berhasil dihapus.',
      type: LabFlowNotificationType.info,
      title: 'Draft dihapus',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();

    super.dispose();
  }

  /// Membuat laboratorium baru.
  ///
  /// Success notification ditampilkan oleh
  /// LaboratoryManagementPage setelah menerima result true.
  Future<void> _save() async {
    FocusScope.of(context).unfocus();

    final isValid = _formKey.currentState?.validate() ?? false;

    if (!isValid || _isLoading) {
      return;
    }

    final isOffline =
        context.read<ConnectivityCubit?>()?.state.isOffline ?? false;
    if (isOffline) {
      await _saveDraftLocally();
      return;
    }

    try {
      final name = _nameController.text.trim();

      final code = _codeController.text.trim().toUpperCase();

      final description = _descriptionController.text.trim();

      final location = _locationController.text.trim();

      /// =====================================================
      /// CREATE LABORATORY
      /// =====================================================

      await context.read<LaboratoryManagementActionCubit>().createLaboratory(
        name: name,
        code: code,
        description: description,
        location: location,
        status: _status,
      );

      final uid = _authService.currentUid;
      if (uid != null && _loadedDraft != null) {
        await _draftStore.removeDraft(uid, _loadedDraft!.draftId);
      }

      if (!mounted) {
        return;
      }

      /// Halaman sebelumnya akan menampilkan
      /// floating success notification.
      context.pop(true);
    } on LaboratoryException catch (error) {
      if (!mounted) {
        return;
      }

      /// Duplicate code dan business rule lain
      /// lebih tepat ditampilkan sebagai warning.
      _showMessage(
        error.message,
        type: LabFlowNotificationType.warning,
        title: 'Laboratorium tidak dapat dibuat',
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      await _saveDraftLocally(
        lastError:
            'Koneksi terputus saat menyimpan. Draft disimpan secara lokal.',
      );
    }
  }

  /// Shared floating notification LabFlow.
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

  String? _requiredValidator(String? value) {
    return value == null
        ? 'Field ini wajib diisi.'
        : LaboratoryService.validateName(value);
  }

  String? _codeValidator(String? value) => value == null
      ? 'Kode laboratorium wajib diisi.'
      : LaboratoryService.validateCode(value);

  String? _locationValidator(String? value) =>
      value == null || value.trim().isEmpty
      ? 'Lokasi laboratorium wajib diisi.'
      : null;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LaboratoryManagementActionCubit, bool>(
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
          'Tambah Laboratorium',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Data Laboratorium',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111111),
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  'Data akan disimpan langsung ke Cloud Firestore.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: Color(0xFF6B7280),
                  ),
                ),

                if (_loadedDraft != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFDDE2D5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.edit_note_rounded,
                          color: Color(0xFF111111),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Draft lokal dimuat',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              LabFlowDraftStatusBadge(
                                status: _loadedDraft!.syncStatus,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Hapus draft lokal',
                          onPressed: _isLoading ? null : _deleteLocalDraft,
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: Color(0xFFBD3232),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                /// =================================================
                /// NAMA
                /// =================================================
                TextFormField(
                  controller: _nameController,
                  validator: _requiredValidator,
                  enabled: !_isLoading,
                  textInputAction: TextInputAction.next,
                  decoration: _inputDecoration(
                    'Nama Laboratorium',
                    'Laboratorium Komputer 1',
                    Icons.science_outlined,
                  ),
                ),

                const SizedBox(height: 16),

                /// =================================================
                /// KODE
                /// =================================================
                TextFormField(
                  controller: _codeController,
                  validator: _codeValidator,
                  enabled: !_isLoading,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  decoration: _inputDecoration(
                    'Kode Laboratorium',
                    'LAB-KOM-01',
                    Icons.qr_code_rounded,
                  ),
                ),

                const SizedBox(height: 16),

                /// =================================================
                /// LOKASI
                /// =================================================
                TextFormField(
                  controller: _locationController,
                  validator: _locationValidator,
                  enabled: !_isLoading,
                  textInputAction: TextInputAction.next,
                  decoration: _inputDecoration(
                    'Lokasi',
                    'Gedung FMIKOM',
                    Icons.location_on_outlined,
                  ),
                ),

                const SizedBox(height: 16),

                /// =================================================
                /// DESKRIPSI
                /// =================================================
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 4,
                  enabled: !_isLoading,
                  textInputAction: TextInputAction.newline,
                  decoration: _inputDecoration(
                    'Deskripsi',
                    'Laboratorium untuk kegiatan praktikum...',
                    Icons.notes_rounded,
                  ),
                ),

                const SizedBox(height: 24),

                /// =================================================
                /// STATUS
                /// =================================================
                const Text(
                  'Status Laboratorium',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7280),
                  ),
                ),

                const SizedBox(height: 8),

                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment<String>(
                      value: 'active',
                      label: Text('Aktif'),
                      icon: Icon(Icons.check_circle_outline),
                    ),

                    ButtonSegment<String>(
                      value: 'inactive',
                      label: Text('Tidak Aktif'),
                      icon: Icon(Icons.block_outlined),
                    ),
                  ],

                  selected: {_status},

                  onSelectionChanged: _isLoading
                      ? null
                      : (selection) {
                          setState(() {
                            _status = selection.first;
                          });
                        },
                ),

                const SizedBox(height: 28),

                /// =================================================
                /// SIMPAN
                /// =================================================
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    onPressed: _isLoading ? null : _save,

                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF111111),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF777777),
                      shape: const StadiumBorder(),
                    ),

                    child: _isLoading
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
                              Icon(Icons.add_business_outlined, size: 20),
                              SizedBox(width: 10),
                              Text(
                                'Simpan Laboratorium',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                  ),
                ),

                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _saveDraftLocally,
                    icon: const Icon(Icons.save_as_outlined, size: 18),
                    label: const Text(
                      'Simpan Draft Lokal',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF111111),
                      side: const BorderSide(color: Color(0xFFD8DDD0)),
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, String hint, IconData icon) {
    return InputDecoration(
      labelText: label,

      hintText: hint,

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
