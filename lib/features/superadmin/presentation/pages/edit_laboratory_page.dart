import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/connectivity/connectivity_cubit.dart';
import '../../../../core/offline/admin_entity_draft_store.dart';
import '../../../../core/offline/conflict_resolution.dart';
import '../../../../shared/presentation/dialogs/labflow_confirmation_dialog.dart';
import '../../../../shared/presentation/dialogs/labflow_conflict_resolution_dialog.dart';
import '../../../../shared/presentation/notifications/labflow_notification.dart';
import '../../../../shared/presentation/states/labflow_connection_error_state.dart';
import '../../../../shared/presentation/states/labflow_loading_state.dart';
import '../../../auth/data/auth_service.dart';
import '../../../laboratory/data/laboratory_service.dart';
import '../../../laboratory/domain/laboratory.dart';
import '../../data/activity_log_service.dart';
import '../cubit/laboratory_management_action_cubit.dart';
import '../cubit/laboratory_detail_cubit.dart';

class EditLaboratoryPage extends StatelessWidget {
  const EditLaboratoryPage({required this.laboratoryId, super.key});
  final String laboratoryId;

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (_) => LaboratoryManagementActionCubit(
          LaboratoryService(),
          ActivityLogService(),
        ),
      ),
      BlocProvider(
        create: (_) =>
            LaboratoryDetailCubit(LaboratoryService())..load(laboratoryId),
      ),
    ],
    child: _EditLaboratoryView(laboratoryId: laboratoryId),
  );
}

class _EditLaboratoryView extends StatefulWidget {
  const _EditLaboratoryView({required this.laboratoryId});

  final String laboratoryId;

  @override
  State<_EditLaboratoryView> createState() => _EditLaboratoryPageState();
}

class _EditLaboratoryPageState extends State<_EditLaboratoryView> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final AdminEntityDraftStore _draftStore =
      SharedPreferencesAdminEntityDraftStore();
  final AuthService _authService = AuthService();

  bool _initialised = false;
  bool get _isSaving => context.read<LaboratoryManagementActionCubit>().state;
  bool get _isDeleting => _isSaving;
  String _status = 'active';
  OfflineEntityDraft? _loadedDraft;
  bool _draftChecked = false;

  static const Map<String, String> _fieldLabels = <String, String>{
    'name': 'Nama Laboratorium',
    'code': 'Kode Laboratorium',
    'location': 'Lokasi',
    'description': 'Deskripsi',
    'status': 'Status',
  };

  /// Snapshot kondisi awal.
  ///
  /// Digunakan untuk mendeteksi perubahan data
  /// serta membuat Activity Log yang sesuai.
  String _originalName = '';
  String _originalCode = '';
  Laboratory? _originalLaboratory;
  bool get _isDirty {
    final original = _originalLaboratory;
    if (original == null) return false;
    return original.name.trim() != _nameController.text.trim() ||
        original.code.trim().toUpperCase() !=
            _codeController.text.trim().toUpperCase() ||
        original.location.trim() != _locationController.text.trim() ||
        original.description.trim() != _descriptionController.text.trim() ||
        original.status != _status;
  }

  @override
  void initState() {
    super.initState();
    _loadLocalDraft();
  }

  Future<void> _loadLocalDraft() async {
    final uid = _authService.currentUid;
    if (uid == null) {
      if (mounted) setState(() => _draftChecked = true);
      return;
    }
    final draft = await _draftStore.readDraftForEntity(
      uid: uid,
      entityType: DraftEntityType.laboratory,
      entityId: widget.laboratoryId,
    );
    if (!mounted) return;
    setState(() {
      _loadedDraft = draft;
      _draftChecked = true;
      if (draft != null) {
        _applyDraftToForm(draft);
      }
    });
  }

  void _applyDraftToForm(OfflineEntityDraft draft) {
    _nameController.text = (draft.data['name'] as String? ?? '');
    _codeController.text = (draft.data['code'] as String? ?? '');
    _locationController.text = (draft.data['location'] as String? ?? '');
    _descriptionController.text = (draft.data['description'] as String? ?? '');
    final draftStatus = (draft.data['status'] as String? ?? 'active');
    if (draftStatus == 'active' || draftStatus == 'inactive') {
      _status = draftStatus;
    }
    if (_originalLaboratory == null && draft.baselineData != null) {
      final base = draft.baselineData!;
      _originalName = (base['name'] as String? ?? '');
      _originalCode = (base['code'] as String? ?? '');
      _originalLaboratory = Laboratory(
        id: widget.laboratoryId,
        name: _originalName,
        code: _originalCode,
        description: (base['description'] as String? ?? ''),
        location: (base['location'] as String? ?? ''),
        status: (base['status'] as String? ?? 'active'),
        updatedAt: draft.baselineUpdatedAt,
      );
      _initialised = true;
    }
  }

  Future<void> _saveDraftLocally({
    DraftSyncStatus syncStatus = DraftSyncStatus.pending,
    String? lastError,
    Map<String, FieldConflict> conflicts = const <String, FieldConflict>{},
  }) async {
    FocusScope.of(context).unfocus();
    final uid = _authService.currentUid;
    final original = _originalLaboratory;
    if (uid == null || original == null) return;
    final now = DateTime.now().toUtc();
    final draftId = OfflineEntityDraft.createDraftIdFor(
      entityType: DraftEntityType.laboratory,
      entityId: widget.laboratoryId,
    );
    final draft = OfflineEntityDraft(
      draftId: draftId,
      ownerUid: uid,
      entityType: DraftEntityType.laboratory,
      entityId: widget.laboratoryId,
      data: <String, Object?>{
        'name': _nameController.text.trim(),
        'code': _codeController.text.trim().toUpperCase(),
        'location': _locationController.text.trim(),
        'description': _descriptionController.text.trim(),
        'status': _status,
      },
      baselineData: _loadedDraft?.baselineData ?? original.toBaselineMap(),
      baselineUpdatedAt: _loadedDraft?.baselineUpdatedAt ?? original.updatedAt,
      createdAt: _loadedDraft?.createdAt ?? now,
      updatedAt: now,
      syncStatus: syncStatus,
      lastError: lastError,
      conflicts: conflicts,
    );
    await _draftStore.saveDraft(uid, draft);
    if (!mounted) return;
    setState(() => _loadedDraft = draft);
    if (syncStatus == DraftSyncStatus.pending) {
      _showMessage(
        'Perubahan laboratorium disimpan sebagai draft lokal.',
        type: LabFlowNotificationType.info,
        title: 'Draft lokal disimpan',
      );
    }
  }

  Future<void> _deleteLocalDraft() async {
    final uid = _authService.currentUid;
    final draft = _loadedDraft;
    if (uid == null || draft == null) return;
    await _draftStore.removeDraft(uid, draft.draftId);
    if (!mounted) return;
    setState(() {
      _loadedDraft = null;
      final original = _originalLaboratory;
      if (original != null) {
        _nameController.text = original.name;
        _codeController.text = original.code;
        _locationController.text = original.location;
        _descriptionController.text = original.description;
        _status = original.status;
      }
    });
    _showMessage(
      'Draft lokal dihapus dan form dikembalikan ke kondisi awal.',
      type: LabFlowNotificationType.info,
      title: 'Draft dihapus',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// Mengisi form satu kali setelah data
  /// berhasil dimuat dari Firestore.
  void _fillForm(Laboratory laboratory) {
    if (_initialised) {
      return;
    }
    _originalName = laboratory.name;
    _originalCode = laboratory.code;
    _originalLaboratory = laboratory;
    if (_loadedDraft != null) {
      _applyDraftToForm(_loadedDraft!);
    } else {
      _nameController.text = laboratory.name;
      _codeController.text = laboratory.code;
      _locationController.text = laboratory.location;
      _descriptionController.text = laboratory.description;
      _status = laboratory.status;
    }
    _initialised = true;
  }

  /// Memperbarui data laboratorium.
  ///
  /// Activity Log dibuat setelah update Firestore berhasil.
  Future<void> _update({
    Map<String, ConflictResolutionDecision>? conflictDecisions,
  }) async {
    FocusScope.of(context).unfocus();
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid || _isSaving || _isDeleting) {
      return;
    }

    final isOffline =
        context.read<ConnectivityCubit?>()?.state.isOffline ?? false;
    if (isOffline) {
      await _saveDraftLocally();
      return;
    }

    try {
      final newName = _nameController.text.trim();
      final newCode = _codeController.text.trim().toUpperCase();
      final newLocation = _locationController.text.trim();
      final newDescription = _descriptionController.text.trim();
      final newStatus = _status;
      final baseline =
          _loadedDraft?.baselineData ?? _originalLaboratory?.toBaselineMap();

      await context.read<LaboratoryManagementActionCubit>().updateLaboratory(
        laboratoryId: widget.laboratoryId,
        name: newName,
        code: newCode,
        description: newDescription,
        location: newLocation,
        status: newStatus,
        original: _originalLaboratory!,
        baselineData: baseline,
        conflictDecisions: conflictDecisions,
      );

      final uid = _authService.currentUid;
      if (uid != null && _loadedDraft != null) {
        await _draftStore.removeDraft(uid, _loadedDraft!.draftId);
      }

      /// Memperbarui snapshot lokal setelah
      /// operasi berhasil.
      _originalName = newName;
      _originalCode = newCode;
      if (!mounted) {
        return;
      }

      /// Notifikasi sukses ditampilkan pada halaman
      /// Laboratory Management setelah menerima
      /// result "updated".
      context.pop('updated');
    } on ConflictDetectedException catch (conflictError) {
      if (!mounted) return;
      await _saveDraftLocally(
        syncStatus: DraftSyncStatus.conflict,
        lastError: conflictError.message,
        conflicts: conflictError.analysis.conflicts,
      );
      if (!mounted) return;
      final decisions = await showLabFlowConflictResolutionDialog(
        context: context,
        analysis: conflictError.analysis,
        fieldLabels: _fieldLabels,
      );
      if (decisions != null && mounted) {
        final resolved = conflictError.analysis.resolveWithDecisions(decisions);
        setState(() {
          _nameController.text = (resolved['name'] as String? ?? '');
          _codeController.text = (resolved['code'] as String? ?? '');
          _locationController.text = (resolved['location'] as String? ?? '');
          _descriptionController.text =
              (resolved['description'] as String? ?? '');
          _status = (resolved['status'] as String? ?? _status);
        });
        await _update(conflictDecisions: decisions);
      }
    } on LaboratoryException catch (error) {
      if (!mounted) {
        return;
      }

      /// Error dari business rule/service ditampilkan
      /// sebagai Warning karena biasanya merupakan
      /// kondisi yang dapat diperbaiki pengguna.
      _showMessage(
        error.message,
        type: LabFlowNotificationType.warning,
        title: 'Perubahan tidak dapat disimpan',
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      await _saveDraftLocally(
        syncStatus: DraftSyncStatus.failed,
        lastError:
            'Koneksi terputus saat menyimpan. Draft disimpan secara lokal.',
      );
      if (!mounted) return;
      _showMessage(
        'Gagal memperbarui laboratorium. Perubahan telah disimpan sebagai draft lokal.',
        type: LabFlowNotificationType.error,
        title: 'Tersimpan sebagai draft',
      );
    }
  }

  /// Menghapus laboratorium.
  ///
  /// Confirmation menggunakan shared
  /// LabFlow Confirmation Dialog.
  ///
  /// LaboratoryService tetap menjadi penjaga utama:
  /// lab yang sudah memiliki riwayat membership
  /// tidak boleh dihapus permanen.
  Future<void> _delete() async {
    if (_isDeleting || _isSaving) {
      return;
    }
    final laboratoryName = _nameController.text.trim();
    final laboratoryCode = _codeController.text.trim().toUpperCase();

    /// =====================================================
    /// SHARED DELETE CONFIRMATION
    /// =====================================================
    final confirmed = await showDeleteConfirmationDialog(
      context: context,
      title: 'Hapus laboratorium ini?',
      description:
          '$laboratoryCode — $laboratoryName akan dihapus permanen '
          'jika belum memiliki riwayat membership. '
          'Tindakan ini tidak dapat dibatalkan.',
      confirmLabel: 'Ya, Hapus Laboratorium',
    );
    if (!confirmed || !mounted) {
      return;
    }
    try {
      /// Simpan identitas sebelum document dihapus.
      ///
      /// Data ini tetap diperlukan untuk Activity Log.
      final deletedName = _originalName.trim();
      final deletedCode = _originalCode.trim().toUpperCase();

      /// =====================================================
      /// DELETE FIRESTORE
      /// =====================================================
      await context.read<LaboratoryManagementActionCubit>().deleteLaboratory(
        laboratoryId: widget.laboratoryId,
        name: deletedName,
        code: deletedCode,
      );
      if (!mounted) {
        return;
      }

      /// Notifikasi sukses akan ditampilkan oleh
      /// halaman Laboratory Management setelah
      /// menerima result "deleted".
      context.pop('deleted');
    } on LaboratoryException catch (error) {
      if (!mounted) {
        return;
      }

      /// Contoh:
      /// Laboratorium mempunyai riwayat membership
      /// sehingga tidak boleh di-hard-delete.
      ///
      /// Ini bukan crash aplikasi sehingga kita gunakan
      /// floating notification bertipe Warning.
      _showMessage(
        error.message,
        type: LabFlowNotificationType.warning,
        title: 'Laboratorium tidak dapat dihapus',
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      /// Unexpected error menggunakan tipe Error.
      _showMessage(
        'Gagal menghapus laboratorium.',
        type: LabFlowNotificationType.error,
        title: 'Penghapusan gagal',
      );
    }
  }

  /// Menampilkan shared floating notification LabFlow.
  ///
  /// Tidak lagi menggunakan SnackBar hitam bawaan Flutter.
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

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Field ini wajib diisi.';
    }
    final original = _originalLaboratory;
    if (original != null && value.trim() == original.name.trim()) {
      return null;
    }
    return LaboratoryService.validateName(value);
  }

  String? _codeValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Kode laboratorium wajib diisi.';
    }
    final original = _originalLaboratory;
    if (original != null &&
        value.trim().toUpperCase() == original.code.trim().toUpperCase()) {
      return null;
    }
    return LaboratoryService.validateCode(value);
  }

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
          'Edit Laboratorium',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: BlocBuilder<LaboratoryDetailCubit, LaboratoryDetailState>(
        builder: (context, state) {
          if (state is LaboratoryDetailLoading || !_draftChecked) {
            return const LabFlowLoadingState(
              title: 'Memuat laboratorium',
              message: 'Mengambil data laboratorium yang dipilih.',
            );
          }
          if (state is LaboratoryDetailFailure) {
            if (_loadedDraft != null && _originalLaboratory != null) {
              return _buildForm();
            }
            return const LabFlowConnectionErrorState(
              title: 'Laboratorium tidak dapat dimuat',
              message:
                  'Data laboratorium tidak dapat diambil saat ini. '
                  'Periksa koneksi Anda lalu coba lagi.',
            );
          }
          final laboratory = (state as LaboratoryDetailLoaded).laboratory;
          _fillForm(laboratory);
          return _buildForm();
        },
      ),
    );
  }

  Widget _buildForm() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Perbarui Laboratorium',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111111),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Perbarui informasi dan status operasional laboratorium.',
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
                              'Draft lokal aktif untuk laboratorium ini',
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
                        onPressed: _isSaving || _isDeleting
                            ? null
                            : _deleteLocalDraft,
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
              /// NAMA LABORATORIUM
              /// =================================================
              TextFormField(
                controller: _nameController,
                onChanged: (_) => setState(() {}),
                validator: _required,
                enabled: !_isSaving && !_isDeleting,
                textInputAction: TextInputAction.next,
                decoration: _inputDecoration(
                  'Nama Laboratorium',
                  Icons.science_outlined,
                ),
              ),
              const SizedBox(height: 16),

              /// =================================================
              /// KODE LABORATORIUM
              /// =================================================
              TextFormField(
                controller: _codeController,
                onChanged: (_) => setState(() {}),
                validator: _codeValidator,
                enabled: !_isSaving && !_isDeleting,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                decoration: _inputDecoration(
                  'Kode Laboratorium',
                  Icons.qr_code_rounded,
                ),
              ),
              const SizedBox(height: 16),

              /// =================================================
              /// LOKASI
              /// =================================================
              TextFormField(
                controller: _locationController,
                onChanged: (_) => setState(() {}),
                validator: _locationValidator,
                enabled: !_isSaving && !_isDeleting,
                textInputAction: TextInputAction.next,
                decoration: _inputDecoration(
                  'Lokasi',
                  Icons.location_on_outlined,
                ),
              ),
              const SizedBox(height: 16),

              /// =================================================
              /// DESKRIPSI
              /// =================================================
              TextFormField(
                controller: _descriptionController,
                onChanged: (_) => setState(() {}),
                maxLines: 4,
                enabled: !_isSaving && !_isDeleting,
                textInputAction: TextInputAction.newline,
                decoration: _inputDecoration('Deskripsi', Icons.notes_rounded),
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
                onSelectionChanged: _isSaving || _isDeleting
                    ? null
                    : (selection) {
                        setState(() {
                          _status = selection.first;
                        });
                      },
              ),
              const SizedBox(height: 28),

              /// =================================================
              /// UPDATE
              /// =================================================
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _isSaving || _isDeleting || !_isDirty
                      ? null
                      : () => _update(),
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
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _isSaving || _isDeleting || !_isDirty
                      ? null
                      : () => _saveDraftLocally(),
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
              const SizedBox(height: 12),

              /// =================================================
              /// DELETE
              /// =================================================
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _isDeleting || _isSaving ? null : _delete,
                  icon: _isDeleting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline),
                  label: Text(
                    _isDeleting ? 'Menghapus...' : 'Hapus Laboratorium',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFBD3232),
                    side: const BorderSide(color: Color(0xFFBD3232)),
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
