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
import '../../../asset/data/asset_service.dart';
import '../../../asset/domain/laboratory_asset.dart';
import '../../../auth/data/auth_service.dart';
import '../../../laboratory/data/lab_membership_service.dart';
import '../../../laboratory/domain/laboratory.dart';
import '../cubit/asset_management_cubit.dart';
import '../cubit/asset_management_state.dart';
import '../widgets/asset_management_widgets.dart';
import '../widgets/lab_admin_bottom_navigation.dart';

class AssetManagementPage extends StatelessWidget {
  const AssetManagementPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) =>
        AssetManagementCubit(LabMembershipService(), AssetService())..start(),
    child: const _AssetManagementView(),
  );
}

class _AssetManagementView extends StatefulWidget {
  const _AssetManagementView();

  @override
  State<_AssetManagementView> createState() => _AssetManagementViewState();
}

class _AssetManagementViewState extends State<_AssetManagementView> {
  final _searchController = TextEditingController();
  final AdminEntityDraftStore _draftStore =
      SharedPreferencesAdminEntityDraftStore();
  final AuthService _authService = AuthService();
  final AssetService _assetService = AssetService();
  List<OfflineEntityDraft> _drafts = const <OfflineEntityDraft>[];

  static const Map<String, String> _fieldLabels = <String, String>{
    'name': 'Nama Aset',
    'code': 'Kode Aset',
    'category': 'Kategori',
    'stock': 'Stock',
    'location': 'Lokasi Aset',
    'description': 'Deskripsi',
    'status': 'Status Aset',
    'condition': 'Kondisi Aset',
    'imageUrl': 'Foto Aset',
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
      entityType: DraftEntityType.asset,
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
    showLabFlowNotification(
      context: context,
      title: 'Draft dihapus',
      message: 'Draft lokal aset telah dihapus.',
      type: LabFlowNotificationType.info,
    );
  }

  Future<void> _resumeDraftEdit(OfflineEntityDraft draft) async {
    if (draft.isCreateDraft) {
      await _createAsset();
      return;
    }
    final assetId = draft.entityId!;
    final result = await context.push<String>(
      '/lab-admin/assets/$assetId/edit',
    );
    await _loadDrafts();
    if (!mounted) return;
    if (result == 'updated') {
      showLabFlowNotification(
        context: context,
        title: 'Aset diperbarui',
        message: 'Data aset berhasil diperbarui.',
        type: LabFlowNotificationType.success,
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
      if (profile.role != 'lab_admin') {
        throw const AssetException(
          'Hanya Lab Admin aktif yang dapat menyinkronkan draft aset.',
        );
      }

      final name = (draft.data['name'] as String? ?? '').trim();
      final code = (draft.data['code'] as String? ?? '').trim().toUpperCase();
      final category = (draft.data['category'] as String? ?? '').trim();
      final location = (draft.data['location'] as String? ?? '').trim();
      final description = (draft.data['description'] as String? ?? '').trim();
      final rawStock = draft.data['stock'];
      final stock = switch (rawStock) {
        final int v => v,
        final num v => v.toInt(),
        final String v => int.tryParse(v) ?? 1,
        _ => 1,
      };
      final condition = (draft.data['condition'] as String? ?? 'good').trim();
      final status = (draft.data['status'] as String? ?? 'available').trim();
      final imageUrl = (draft.data['imageUrl'] as String? ?? '').trim();

      if (draft.isCreateDraft) {
        final laboratoryId =
            (draft.data['laboratoryId'] as String? ?? '').trim();
        await _assetService.createAsset(
          laboratoryId: laboratoryId,
          code: code,
          name: name,
          category: category,
          description: description,
          location: location,
          stock: stock,
          condition: condition,
          imageUrl: imageUrl,
        );
      } else {
        await _assetService.updateAsset(
          assetId: draft.entityId!,
          code: code,
          name: name,
          category: category,
          description: description,
          location: location,
          stock: stock,
          status: status,
          condition: condition,
          imageUrl: imageUrl,
          baselineData: draft.baselineData,
          conflictDecisions: conflictDecisions,
        );
      }

      await _draftStore.removeDraft(uid, draft.draftId);
      await _loadDrafts();
      if (!mounted) return;
      showLabFlowNotification(
        context: context,
        title: 'Sinkronisasi berhasil',
        message: 'Draft aset $code berhasil disinkronkan ke server.',
        type: LabFlowNotificationType.success,
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
        final AssetException e => e.message,
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
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _createAsset() async {
    final created = await context.push<bool>('/lab-admin/assets/create');
    await _loadDrafts();
    if (!mounted || created != true) return;
    showLabFlowNotification(
      context: context,
      title: 'Aset berhasil dibuat',
      message: 'Aset baru berhasil ditambahkan ke inventaris laboratorium.',
      type: LabFlowNotificationType.success,
    );
  }

  Future<void> _openAssetDetail(LaboratoryAsset asset) async {
    final result = await context.push<String>('/lab-admin/assets/${asset.id}');
    await _loadDrafts();
    if (!mounted || result != 'deleted') return;
    showLabFlowNotification(
      context: context,
      title: 'Aset berhasil dihapus',
      message: '${asset.name} telah dihapus dari inventaris.',
      type: LabFlowNotificationType.success,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF6F9EF),
    appBar: AppBar(
      backgroundColor: const Color(0xFFF6F9EF),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      title: const Text(
        'Inventaris Aset',
        style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF111111)),
      ),
      actions: [
        IconButton(
          tooltip: 'Tambah aset',
          onPressed: _createAsset,
          icon: const Icon(Icons.add_rounded),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: BlocBuilder<AssetManagementCubit, AssetManagementState>(
      builder: (context, state) => _buildBody(context, state),
    ),
    bottomNavigationBar: const LabAdminBottomNavigation(currentIndex: 1),
  );

  Widget _buildBody(BuildContext context, AssetManagementState state) {
    switch (state.status) {
      case AssetManagementStatus.initial:
      case AssetManagementStatus.loading:
        return const LabFlowLoadingState(
          title: 'Memuat inventaris',
          message: 'Menyiapkan laboratorium dan aset terbaru.',
        );
      case AssetManagementStatus.failure:
        return LabFlowConnectionErrorState(
          title: 'Inventaris tidak dapat dimuat',
          message: state.errorMessage,
          onRetry: context.read<AssetManagementCubit>().retry,
        );
      case AssetManagementStatus.noMembership:
        return AssetManagementEmptyState.noMembership();
      case AssetManagementStatus.noLaboratory:
        return AssetManagementEmptyState.noLaboratory();
      case AssetManagementStatus.loaded:
        final laboratory = state.selectedLaboratory;
        if (laboratory == null) return const SizedBox.shrink();
        return _buildInventory(context, state, laboratory);
    }
  }

  Widget _buildInventory(
    BuildContext context,
    AssetManagementState state,
    Laboratory laboratory,
  ) {
    final filteredAssets = state.filteredAssets;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: _laboratorySelector(context, state, laboratory),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _searchField(context, state),
        ),
        const SizedBox(height: 14),
        _statusFilters(context, state),
        const SizedBox(height: 10),
        Expanded(child: _assetList(context, state, laboratory, filteredAssets)),
      ],
    );
  }

  Widget _laboratorySelector(
    BuildContext context,
    AssetManagementState state,
    Laboratory selected,
  ) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFF111111),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            color: Color(0xFFB9F33D),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.science_outlined, color: Color(0xFF111111)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Laboratorium aktif',
                style: TextStyle(fontSize: 11, color: Color(0xFFB8BCB3)),
              ),
              const SizedBox(height: 4),
              Text(
                selected.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${selected.code} · ${selected.location}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Color(0xFFB8BCB3)),
              ),
            ],
          ),
        ),
        if (state.laboratories.length > 1)
          Theme(
            data: Theme.of(context).copyWith(canvasColor: Colors.white),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: state.selectedLabId,
                icon: const Icon(
                  Icons.expand_more_rounded,
                  color: Colors.white,
                ),
                items: state.laboratories
                    .map(
                      (lab) => DropdownMenuItem(
                        value: lab.id,
                        child: Text(lab.code),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  _searchController.clear();
                  context.read<AssetManagementCubit>().selectLaboratory(value);
                },
              ),
            ),
          ),
      ],
    ),
  );

  Widget _searchField(BuildContext context, AssetManagementState state) =>
      TextField(
        controller: _searchController,
        onChanged: context.read<AssetManagementCubit>().updateSearch,
        decoration: InputDecoration(
          hintText: 'Cari nama, kode, kategori, atau lokasi...',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: state.searchQuery.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Hapus pencarian',
                  onPressed: () {
                    _searchController.clear();
                    context.read<AssetManagementCubit>().updateSearch('');
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: const BorderSide(color: Color(0xFFDDE2D5)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: const BorderSide(color: Color(0xFFDDE2D5)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: const BorderSide(color: Color(0xFF111111), width: 1.5),
          ),
        ),
      );

  Widget _statusFilters(BuildContext context, AssetManagementState state) =>
      SizedBox(
        height: 44,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          scrollDirection: Axis.horizontal,
          children: [
            _filterChip(context, state, 'Semua', AssetStatusFilter.all),
            const SizedBox(width: 8),
            _filterChip(
              context,
              state,
              'Available',
              AssetStatusFilter.available,
            ),
            const SizedBox(width: 8),
            _filterChip(context, state, 'Borrowed', AssetStatusFilter.borrowed),
            const SizedBox(width: 8),
            _filterChip(
              context,
              state,
              'Maintenance',
              AssetStatusFilter.maintenance,
            ),
            const SizedBox(width: 8),
            _filterChip(context, state, 'Inactive', AssetStatusFilter.inactive),
          ],
        ),
      );

  Widget _filterChip(
    BuildContext context,
    AssetManagementState state,
    String label,
    AssetStatusFilter filter,
  ) {
    final selected = state.statusFilter == filter;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) =>
          context.read<AssetManagementCubit>().selectStatus(filter),
      selectedColor: const Color(0xFF111111),
      backgroundColor: Colors.white,
      side: BorderSide(
        color: selected ? const Color(0xFF111111) : const Color(0xFFDDE2D5),
      ),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: selected ? const Color(0xFFB9F33D) : const Color(0xFF111111),
      ),
      shape: const StadiumBorder(),
    );
  }

  Widget _assetList(
    BuildContext context,
    AssetManagementState state,
    Laboratory laboratory,
    List<LaboratoryAsset> assets,
  ) {
    if (state.assets.isEmpty) {
      return AssetManagementEmptyState.noAssets(laboratory);
    }
    if (assets.isEmpty) {
      return const LabFlowNoSearchResultsState(
        title: 'Aset tidak ditemukan',
        message: 'Coba ubah kata pencarian atau filter status yang digunakan.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      itemCount: assets.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          final connectivity = context.watch<ConnectivityCubit?>();
          final isOnline =
              connectivity == null ||
              connectivity.state.status != ConnectivityStatus.offline;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_drafts.isNotEmpty) ...[
                LabFlowOfflineDraftsPanel(
                  drafts: _drafts,
                  isOnline: isOnline,
                  titleBuilder: (draft) {
                    final name = (draft.data['name'] as String? ?? '').trim();
                    final code = (draft.data['code'] as String? ?? '').trim();
                    final label = name.isNotEmpty ? name : 'Aset Tanpa Nama';
                    return draft.isCreateDraft
                        ? '[Buat Baru] $label'
                        : '[Edit] ${code.isNotEmpty ? "$code · " : ""}$label';
                  },
                  subtitleBuilder: (draft) {
                    final cat =
                        (draft.data['category'] as String? ?? '-').trim();
                    final loc =
                        (draft.data['location'] as String? ?? '-').trim();
                    return 'Kategori: ${cat.isEmpty ? "-" : cat} · Lokasi: ${loc.isEmpty ? "-" : loc}';
                  },
                  onResumeEdit: _resumeDraftEdit,
                  onSyncDraft: _syncDraft,
                  onDeleteDraft: _deleteDraft,
                ),
                const SizedBox(height: 14),
              ],
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(
                  '${assets.length} dari ${state.assets.length} aset',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF7A8190),
                  ),
                ),
              ),
            ],
          );
        }
        final asset = assets[index - 1];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: LaboratoryAssetCard(
            asset: asset,
            onTap: () => _openAssetDetail(asset),
          ),
        );
      },
    );
  }
}
