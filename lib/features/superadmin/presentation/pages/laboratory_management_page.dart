import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:go_router/go_router.dart';

import '../../../../core/connectivity/connectivity_cubit.dart';
import '../../../../core/connectivity/connectivity_state.dart';
import '../../../../core/offline/admin_entity_draft_store.dart';
import '../../../../core/offline/conflict_resolution.dart';
import '../../../../shared/presentation/dialogs/labflow_conflict_resolution_dialog.dart';
import '../../../../shared/presentation/notifications/labflow_notification.dart';

import '../../../../shared/presentation/states/labflow_connection_error_state.dart';

import '../../../../shared/presentation/states/labflow_loading_state.dart';
import '../../../../shared/presentation/states/labflow_no_search_results_state.dart';

import '../../../auth/data/auth_service.dart';
import '../../../laboratory/data/laboratory_service.dart';

import '../../../laboratory/domain/laboratory.dart';

import '../../data/activity_log_service.dart';
import '../cubit/laboratory_directory_cubit.dart';
import '../cubit/laboratory_management_action_cubit.dart';

import '../widgets/superadmin_bottom_navigation.dart';

enum _LaboratoryFilter { all, active, inactive }

class LaboratoryManagementPage extends StatelessWidget {
  const LaboratoryManagementPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => LaboratoryDirectoryCubit(LaboratoryService())..start(),
    child: const _LaboratoryManagementView(),
  );
}

class _LaboratoryManagementView extends StatefulWidget {
  const _LaboratoryManagementView();

  @override
  State<_LaboratoryManagementView> createState() =>
      _LaboratoryManagementPageState();
}

class _LaboratoryManagementPageState extends State<_LaboratoryManagementView> {
  final TextEditingController _searchController = TextEditingController();
  final AdminEntityDraftStore _draftStore =
      SharedPreferencesAdminEntityDraftStore();
  final AuthService _authService = AuthService();
  late final LaboratoryManagementActionCubit _actionCubit =
      LaboratoryManagementActionCubit(
        LaboratoryService(),
        ActivityLogService(),
      );

  _LaboratoryFilter _selectedFilter = _LaboratoryFilter.all;
  List<OfflineEntityDraft> _drafts = const <OfflineEntityDraft>[];

  static const Map<String, String> _fieldLabels = <String, String>{
    'name': 'Nama Laboratorium',
    'code': 'Kode Laboratorium',
    'location': 'Lokasi',
    'description': 'Deskripsi',
    'status': 'Status',
  };

  @override
  void initState() {
    super.initState();
    _loadDrafts();
  }

  Future<void> _loadDrafts() async {
    final uid = _authService.currentUid;
    if (uid == null) return;
    final drafts = await _draftStore.listDrafts(
      uid,
      entityType: DraftEntityType.laboratory,
    );
    if (!mounted) return;
    setState(() => _drafts = drafts);
  }

  Future<void> _deleteDraft(OfflineEntityDraft draft) async {
    final uid = _authService.currentUid;
    if (uid == null) return;
    await _draftStore.removeDraft(uid, draft.draftId);
    await _loadDrafts();
    if (!mounted) return;
    _showSuccessMessage(
      title: 'Draft dihapus',
      message: 'Draft lokal laboratorium telah dihapus.',
    );
  }

  Future<void> _resumeDraftEdit(OfflineEntityDraft draft) async {
    if (draft.isCreateDraft) {
      final created = await context.push<bool>('/superadmin/labs/create');
      await _loadDrafts();
      if (!mounted) return;
      if (created == true) {
        _showSuccessMessage(
          title: 'Laboratorium dibuat',
          message: 'Laboratorium baru berhasil ditambahkan ke sistem.',
        );
      }
      return;
    }
    final entityId = draft.entityId!;
    final result = await context.push<String>(
      '/superadmin/labs/$entityId/edit',
    );
    await _loadDrafts();
    if (!mounted) return;
    if (result == 'updated') {
      _showSuccessMessage(
        title: 'Laboratorium diperbarui',
        message: 'Data laboratorium berhasil diperbarui.',
      );
    }
  }

  Future<void> _syncDraft(
    OfflineEntityDraft draft, {
    Map<String, ConflictResolutionDecision>? conflictDecisions,
  }) async {
    final uid = _authService.currentUid;
    if (uid == null) return;

    final syncingDraft = draft.copyWith(
      syncStatus: DraftSyncStatus.syncing,
      clearError: true,
    );
    await _draftStore.saveDraft(uid, syncingDraft);
    await _loadDrafts();

    try {
      final profile = await _authService.getCurrentUserProfile(
        forceRefresh: true,
      );
      if (profile.role != 'superadmin') {
        throw const LaboratoryException(
          'Hanya Superadmin aktif yang dapat menyinkronkan draft laboratorium.',
        );
      }

      final name = (draft.data['name'] as String? ?? '').trim();
      final code = (draft.data['code'] as String? ?? '').trim().toUpperCase();
      final location = (draft.data['location'] as String? ?? '').trim();
      final description = (draft.data['description'] as String? ?? '').trim();
      final status = (draft.data['status'] as String? ?? 'active').trim();

      if (draft.isCreateDraft) {
        await _actionCubit.createLaboratory(
          name: name,
          code: code,
          description: description,
          location: location,
          status: status,
        );
      } else {
        final base = draft.baselineData ?? const <String, Object?>{};
        final original = Laboratory(
          id: draft.entityId!,
          name: (base['name'] as String? ?? name),
          code: (base['code'] as String? ?? code),
          description: (base['description'] as String? ?? description),
          location: (base['location'] as String? ?? location),
          status: (base['status'] as String? ?? status),
          updatedAt: draft.baselineUpdatedAt,
        );
        await _actionCubit.updateLaboratory(
          laboratoryId: draft.entityId!,
          name: name,
          code: code,
          description: description,
          location: location,
          status: status,
          original: original,
          baselineData: draft.baselineData,
          conflictDecisions: conflictDecisions,
        );
      }

      await _draftStore.removeDraft(uid, draft.draftId);
      await _loadDrafts();
      if (!mounted) return;
      _showSuccessMessage(
        title: 'Sinkronisasi berhasil',
        message: 'Draft laboratorium $code berhasil disinkronkan ke server.',
      );
    } on ConflictDetectedException catch (conflictError) {
      final conflictDraft = draft.copyWith(
        syncStatus: DraftSyncStatus.conflict,
        lastError: conflictError.message,
        conflicts: conflictError.analysis.conflicts,
        updatedAt: DateTime.now().toUtc(),
      );
      await _draftStore.saveDraft(uid, conflictDraft);
      await _loadDrafts();
      if (!mounted) return;
      final decisions = await showLabFlowConflictResolutionDialog(
        context: context,
        analysis: conflictError.analysis,
        fieldLabels: _fieldLabels,
      );
      if (decisions != null && mounted) {
        final resolved = conflictError.analysis.resolveWithDecisions(decisions);
        final updatedDraft = conflictDraft.copyWith(
          data: resolved,
          updatedAt: DateTime.now().toUtc(),
        );
        await _draftStore.saveDraft(uid, updatedDraft);
        await _syncDraft(updatedDraft, conflictDecisions: decisions);
      }
    } on Object catch (error) {
      final message = switch (error) {
        final LaboratoryException e => e.message,
        final AuthServiceException e => e.message,
        _ => 'Sinkronisasi gagal. Periksa koneksi Anda lalu coba lagi.',
      };
      final failedDraft = draft.copyWith(
        syncStatus: DraftSyncStatus.failed,
        lastError: message,
        updatedAt: DateTime.now().toUtc(),
      );
      await _draftStore.saveDraft(uid, failedDraft);
      await _loadDrafts();
      if (!mounted) return;
      showLabFlowNotification(
        context: context,
        title: 'Sinkronisasi belum berhasil',
        message: message,
        type: LabFlowNotificationType.warning,
      );
    }
  }

  @override
  void dispose() {
    _actionCubit.close();
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
            /// Header halaman sesuai reference Figma.

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),

              child: _buildHeader(),
            ),

            const SizedBox(height: 20),

            /// Search dan filter.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),

              child: _buildSearchBar(),
            ),

            const SizedBox(height: 20),

            /// Data laboratorium realtime dari Firestore.
            Expanded(
              child:
                  BlocBuilder<
                    LaboratoryDirectoryCubit,
                    LaboratoryDirectoryState
                  >(
                    builder: (context, state) {
                      if (state is LaboratoryDirectoryLoading) {
                        return const LabFlowLoadingState(
                          title: 'Memuat laboratorium',

                          message: 'Mengambil daftar laboratorium terbaru.',
                        );
                      }

                      if (state is LaboratoryDirectoryFailure) {
                        return const LabFlowConnectionErrorState(
                          title: 'Laboratorium tidak dapat dimuat',

                          message:
                              'Data laboratorium tidak dapat diambil saat ini. '
                              'Periksa koneksi Anda lalu coba lagi.',
                        );
                      }

                      final loaded = state as LaboratoryDirectoryLoaded;
                      final laboratories = loaded.laboratories;
                      final filteredLaboratories = loaded.visibleLaboratories;

                      if (laboratories.isEmpty) {
                        return _buildEmptyState();
                      }

                      if (filteredLaboratories.isEmpty) {
                        return const LabFlowNoSearchResultsState(
                          title: 'Laboratorium tidak ditemukan',
                          message: 'Coba ubah kata pencarian atau filter yang digunakan.',
                        );
                      }

                      return ListView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),

                        children: [
                          if (_drafts.isNotEmpty) ...[
                            Builder(
                              builder: (context) {
                                final connectivity = context
                                    .watch<ConnectivityCubit?>();
                                final isOnline =
                                    connectivity == null ||
                                    connectivity.state.status !=
                                        ConnectivityStatus.offline;
                                return LabFlowOfflineDraftsPanel(
                                  drafts: _drafts,
                                  isOnline: isOnline,
                                  titleBuilder: (draft) {
                                    final name =
                                        (draft.data['name'] as String? ?? '')
                                            .trim();
                                    final code =
                                        (draft.data['code'] as String? ?? '')
                                            .trim();
                                    final label = name.isNotEmpty
                                        ? name
                                        : 'Laboratorium Tanpa Nama';
                                    return draft.isCreateDraft
                                        ? '[Buat Baru] $label'
                                        : '[Edit] ${code.isNotEmpty ? "$code · " : ""}$label';
                                  },
                                  subtitleBuilder: (draft) {
                                    final loc =
                                        (draft.data['location'] as String? ??
                                                '-')
                                            .trim();
                                    return 'Lokasi: ${loc.isEmpty ? "-" : loc}';
                                  },
                                  onResumeEdit: _resumeDraftEdit,
                                  onSyncDraft: _syncDraft,
                                  onDeleteDraft: _deleteDraft,
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                          ],
                          for (
                            int index = 0;

                            index < filteredLaboratories.length;

                            index++
                          ) ...[
                            _buildLaboratoryCard(filteredLaboratories[index]),

                            if (index != filteredLaboratories.length - 1)
                              const SizedBox(height: 14),
                          ],

                          const SizedBox(height: 22),

                          /// Ringkasan sederhana menggunakan

                          /// data yang tersedia.
                          _buildSummary(laboratories),

                          const SizedBox(height: 12),
                        ],
                      );
                    },
                  ),
            ),
          ],
        ),
      ),

      bottomNavigationBar: const SuperadminBottomNavigation(currentIndex: 1),
    );
  }

  /// Header besar + tombol tambah.

  Widget _buildHeader() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Laboratorium',

            style: TextStyle(
              fontSize: 30,

              height: 1,

              fontWeight: FontWeight.w800,

              color: Color(0xFF111111),
            ),
          ),
        ),

        const SizedBox(width: 16),

        Material(
          color: Colors.white,

          shape: const CircleBorder(),

          child: InkWell(
            customBorder: const CircleBorder(),

            onTap: _createLaboratory,

            child: const SizedBox(
              width: 52,

              height: 52,

              child: Icon(
                Icons.add_rounded,

                size: 28,

                color: Color(0xFF111111),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Search field mengikuti visual LabFlow.

  Widget _buildSearchBar() {
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

              onChanged: context.read<LaboratoryDirectoryCubit>().setQuery,

              textInputAction: TextInputAction.search,

              decoration: const InputDecoration(
                hintText: 'Cari laboratorium...',

                hintStyle: TextStyle(fontSize: 14, color: Color(0xFF8B929F)),

                border: InputBorder.none,

                isDense: true,
              ),
            ),
          ),

          IconButton(
            tooltip: 'Filter laboratorium',

            onPressed: _openFilterSheet,

            icon: Icon(
              Icons.tune_rounded,

              color: _selectedFilter == _LaboratoryFilter.all
                  ? const Color(0xFF111111)
                  : const Color(0xFF6C9B00),
            ),
          ),

          const SizedBox(width: 6),
        ],
      ),
    );
  }

  /// Card laboratorium.

  Widget _buildLaboratoryCard(Laboratory laboratory) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),

      onTap: () async {
        final result = await context.push<String>(
          '/superadmin/labs/${laboratory.id}/edit',
        );
        await _loadDrafts();

        if (!mounted) {
          return;
        }

        if (result == 'updated') {
          _showSuccessMessage(
            title: 'Laboratorium diperbarui',

            message: '${laboratory.code} berhasil diperbarui.',
          );
        } else if (result == 'deleted') {
          _showSuccessMessage(
            title: 'Laboratorium dihapus',

            message: '${laboratory.code} berhasil dihapus dari sistem.',
          );
        }
      },

      child: Container(
        width: double.infinity,

        padding: const EdgeInsets.fromLTRB(16, 18, 14, 18),

        decoration: BoxDecoration(
          color: Colors.white,

          borderRadius: BorderRadius.circular(24),
        ),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            Row(
              children: [
                SizedBox(
                  width: 30,

                  height: 30,

                  child: Icon(
                    _laboratoryIcon(laboratory.name),

                    size: 26,

                    color: const Color(0xFF111111),
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Text(
                    laboratory.name,

                    maxLines: 2,

                    overflow: TextOverflow.ellipsis,

                    style: const TextStyle(
                      fontSize: 17,

                      height: 1.15,

                      fontWeight: FontWeight.w800,

                      color: Color(0xFF111111),
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                const Icon(
                  Icons.north_east_rounded,

                  size: 20,

                  color: Color(0xFF111111),
                ),
              ],
            ),

            const SizedBox(height: 18),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Expanded(child: _buildInformation(laboratory.code, 'Kode')),

                const SizedBox(width: 10),

                Expanded(
                  flex: 2,

                  child: _buildInformation(laboratory.location, 'Lokasi'),
                ),

                const SizedBox(width: 10),

                Expanded(child: _buildStatusInformation(laboratory.isActive)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Informasi kecil di bagian bawah card.

  Widget _buildInformation(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        Text(
          value,

          maxLines: 2,

          overflow: TextOverflow.ellipsis,

          style: const TextStyle(
            fontSize: 12,

            height: 1.25,

            fontWeight: FontWeight.w600,

            color: Color(0xFF111111),
          ),
        ),

        const SizedBox(height: 3),

        Text(
          label,

          style: const TextStyle(fontSize: 10, color: Color(0xFF8B929F)),
        ),
      ],
    );
  }

  Widget _buildStatusInformation(bool isActive) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        Text(
          isActive ? 'Aktif' : 'Tidak Aktif',

          maxLines: 1,

          style: TextStyle(
            fontSize: 12,

            fontWeight: FontWeight.w700,

            color: isActive ? const Color(0xFF188A55) : const Color(0xFFC93434),
          ),
        ),

        const SizedBox(height: 3),

        const Text(
          'Status',

          style: TextStyle(fontSize: 10, color: Color(0xFF8B929F)),
        ),
      ],
    );
  }

  /// Icon berdasarkan jenis/nama laboratorium.

  IconData _laboratoryIcon(String name) {
    final normalized = name.toLowerCase();

    if (normalized.contains('iot') ||
        normalized.contains('internet of things')) {
      return Icons.sensors_rounded;
    }

    if (normalized.contains('jaringan') || normalized.contains('network')) {
      return Icons.router_outlined;
    }

    if (normalized.contains('multimedia')) {
      return Icons.live_tv_outlined;
    }

    if (normalized.contains('elektronika') ||
        normalized.contains('electronic')) {
      return Icons.developer_board_outlined;
    }

    if (normalized.contains('komputer') ||
        normalized.contains('computer') ||
        normalized.contains('kom')) {
      return Icons.desktop_windows_outlined;
    }

    return Icons.science_outlined;
  }

  /// Ringkasan jumlah laboratorium.

  Widget _buildSummary(List<Laboratory> laboratories) {
    final activeCount = laboratories
        .where((laboratory) => laboratory.isActive)
        .length;

    return Text(
      '${laboratories.length} laboratorium · '
      '$activeCount aktif',

      style: const TextStyle(fontSize: 12, color: Color(0xFF7A8190)),
    );
  }

  /// Filter status melalui bottom sheet.

  Future<void> _openFilterSheet() async {
    final result = await showModalBottomSheet<_LaboratoryFilter>(
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
                  'Filter Laboratorium',

                  style: TextStyle(
                    fontSize: 22,

                    fontWeight: FontWeight.w800,

                    color: Color(0xFF111111),
                  ),
                ),

                const SizedBox(height: 16),

                _buildFilterOption(
                  context: context,

                  value: _LaboratoryFilter.all,

                  icon: Icons.apps_rounded,

                  label: 'Semua Laboratorium',
                ),

                _buildFilterOption(
                  context: context,

                  value: _LaboratoryFilter.active,

                  icon: Icons.check_circle_outline_rounded,

                  label: 'Aktif',
                ),

                _buildFilterOption(
                  context: context,

                  value: _LaboratoryFilter.inactive,

                  icon: Icons.block_rounded,

                  label: 'Tidak Aktif',
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
      _selectedFilter = result;
    });
    context.read<LaboratoryDirectoryCubit>().setStatus(switch (result) {
      _LaboratoryFilter.all => 'all',
      _LaboratoryFilter.active => 'active',
      _LaboratoryFilter.inactive => 'inactive',
    });
  }

  Widget _buildFilterOption({
    required BuildContext context,

    required _LaboratoryFilter value,

    required IconData icon,

    required String label,
  }) {
    final selected = _selectedFilter == value;

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

  /// Membuka form Create Laboratory.

  Future<void> _createLaboratory() async {
    final created = await context.push<bool>('/superadmin/labs/create');
    await _loadDrafts();

    if (!mounted) {
      return;
    }

    if (created == true) {
      _showSuccessMessage(
        title: 'Laboratorium dibuat',

        message: 'Laboratorium baru berhasil ditambahkan ke sistem.',
      );
    }
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),

        child: Column(
          mainAxisSize: MainAxisSize.min,

          children: [
            Icon(Icons.science_outlined, size: 56),

            SizedBox(height: 16),

            Text(
              'Belum ada laboratorium',

              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),

            SizedBox(height: 8),

            Text(
              'Tambahkan laboratorium pertama melalui tombol + di atas.',

              textAlign: TextAlign.center,

              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }

  /// Shared floating notification untuk operasi sukses.

  ///

  /// Menggantikan SnackBar hitam bawaan Flutter.

  void _showSuccessMessage({required String title, required String message}) {
    showLabFlowNotification(
      context: context,

      title: title,

      message: message,

      type: LabFlowNotificationType.success,
    );
  }
}
