import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/connectivity/connectivity_cubit.dart';
import '../../../../core/offline/admin_entity_draft_store.dart';
import '../../../../shared/presentation/dialogs/labflow_conflict_resolution_dialog.dart';
import '../../../../shared/presentation/navigation/labflow_back_fallback.dart';

import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../shared/presentation/notifications/labflow_notification.dart';

import '../../../../shared/presentation/states/labflow_connection_error_state.dart';

import '../../../../shared/presentation/states/labflow_loading_state.dart';

import '../../../asset/data/asset_image_service.dart';
import '../../../asset/data/asset_service.dart';
import '../../../auth/data/auth_service.dart';

import '../../../laboratory/data/lab_membership_service.dart';

import '../../../laboratory/domain/lab_membership.dart';

import '../../../laboratory/domain/laboratory.dart';

class CreateAssetPage extends StatefulWidget {
  const CreateAssetPage({this.draftId, super.key});

  final String? draftId;

  @override
  State<CreateAssetPage> createState() => _CreateAssetPageState();
}

class _CreateAssetPageState extends State<CreateAssetPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();

  final TextEditingController _codeController = TextEditingController();

  final TextEditingController _categoryController = TextEditingController();

  final TextEditingController _stockController = TextEditingController(
    text: '1',
  );

  final TextEditingController _locationController = TextEditingController();

  final TextEditingController _descriptionController = TextEditingController();

  final LabMembershipService _membershipService = LabMembershipService();

  final AssetService _assetService = AssetService();
  final AssetImageService _assetImageService = AssetImageService();
  final AdminEntityDraftStore _draftStore =
      SharedPreferencesAdminEntityDraftStore();
  final AuthService _authService = AuthService();

  XFile? _selectedImage;

  String _condition = 'good';

  String? _selectedLabId;

  bool _isLoading = false;
  OfflineEntityDraft? _loadedDraft;

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
        OfflineEntityDraft.createDraftIdFor(entityType: DraftEntityType.asset);
    final draft = await _draftStore.readDraft(uid, targetId);
    if (draft == null || !mounted) return;
    setState(() {
      _loadedDraft = draft;
      _nameController.text = (draft.data['name'] as String? ?? '');
      _codeController.text = (draft.data['code'] as String? ?? '');
      _categoryController.text = (draft.data['category'] as String? ?? '');
      _stockController.text = '${draft.data['stock'] ?? 1}';
      _locationController.text = (draft.data['location'] as String? ?? '');
      _descriptionController.text =
          (draft.data['description'] as String? ?? '');
      final savedCond = (draft.data['condition'] as String? ?? 'good');
      if (savedCond == 'good' ||
          savedCond == 'minor_damage' ||
          savedCond == 'damaged') {
        _condition = savedCond;
      }
      final savedLabId = (draft.data['laboratoryId'] as String?)?.trim();
      if (savedLabId != null && savedLabId.isNotEmpty) {
        _selectedLabId = savedLabId;
      }
    });
  }

  Future<void> _saveDraftLocally(
    String laboratoryId, {
    String? lastError,
  }) async {
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
        OfflineEntityDraft.createDraftIdFor(entityType: DraftEntityType.asset);
    final stock = int.tryParse(_stockController.text.trim()) ?? 1;
    final draft = OfflineEntityDraft(
      draftId: draftId,
      ownerUid: uid,
      entityType: DraftEntityType.asset,
      data: <String, Object?>{
        'laboratoryId': laboratoryId.trim(),
        'name': _nameController.text.trim(),
        'code': _codeController.text.trim().toUpperCase(),
        'category': _categoryController.text.trim(),
        'stock': stock < 1 ? 1 : stock,
        'location': _locationController.text.trim(),
        'description': _descriptionController.text.trim(),
        'condition': _condition,
        'imageUrl': (_loadedDraft?.data['imageUrl'] as String? ?? ''),
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
      'Draft aset tersimpan secara lokal. Anda dapat menyinkronkannya secara manual saat online.',
      title: 'Draft lokal disimpan',
      type: LabFlowNotificationType.info,
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
      'Draft lokal aset berhasil dihapus.',
      title: 'Draft dihapus',
      type: LabFlowNotificationType.info,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();

    _codeController.dispose();

    _categoryController.dispose();

    _stockController.dispose();

    _locationController.dispose();

    _descriptionController.dispose();

    super.dispose();
  }

  Future<void> _save(String laboratoryId) async {
    FocusScope.of(context).unfocus();

    final isValid = _formKey.currentState?.validate() ?? false;

    if (!isValid || _isLoading) {
      return;
    }

    final isOffline =
        context.read<ConnectivityCubit?>()?.state.isOffline ?? false;
    if (isOffline) {
      await _saveDraftLocally(laboratoryId);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final name = _nameController.text.trim();

      final code = _codeController.text.trim().toUpperCase();

      final category = _categoryController.text.trim();

      final location = _locationController.text.trim();

      final description = _descriptionController.text.trim();

      final stock = int.tryParse(_stockController.text.trim()) ?? 0;

      var imageUrl = '';
      if (_selectedImage != null) {
        imageUrl = await _assetImageService.uploadAssetImage(
          image: _selectedImage!,
          laboratoryId: laboratoryId,
        );
      }

      await _assetService.createAsset(
        laboratoryId: laboratoryId,
        code: code,
        name: name,
        category: category,
        description: description,
        location: location,
        stock: stock,
        condition: _condition,
        imageUrl: imageUrl,
      );

      final uid = _authService.currentUid;
      if (uid != null && _loadedDraft != null) {
        await _draftStore.removeDraft(uid, _loadedDraft!.draftId);
      }

      if (!mounted) {
        return;
      }

      context.pop(true);
    } on AssetImageException catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        error.message,
        title: 'Upload foto gagal',
        type: LabFlowNotificationType.warning,
      );
    } on AssetException catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        error.message,

        title: 'Aset tidak dapat dibuat',

        type: LabFlowNotificationType.warning,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      await _saveDraftLocally(
        laboratoryId,
        lastError:
            'Koneksi terputus saat menyimpan. Draft disimpan secara lokal.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickImage() async {
    if (_isLoading) {
      return;
    }

    try {
      final image = await _assetImageService.pickFromGallery();

      if (image == null || !mounted) {
        return;
      }

      setState(() {
        _selectedImage = image;
      });
    } on AssetImageException catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        error.message,
        title: 'Foto tidak dapat dipilih',
        type: LabFlowNotificationType.warning,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Terjadi kesalahan saat memilih foto.',
        title: 'Pemilihan foto gagal',
        type: LabFlowNotificationType.error,
      );
    }
  }

  void _showMessage(
    String message, {

    required String title,

    LabFlowNotificationType type = LabFlowNotificationType.error,
  }) {
    showLabFlowNotification(
      context: context,

      title: title,

      message: message,

      type: type,
    );
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Field ini wajib diisi.';
    }

    return null;
  }

  String? _stockValidator(String? value) {
    final stock = int.tryParse(value?.trim() ?? '');

    if (stock == null) {
      return 'Stock harus berupa angka.';
    }

    if (stock < 1) {
      return 'Stock minimal 1.';
    }

    return null;
  }

  String _resolveSelectedLabId(List<Laboratory> assignedLaboratories) {
    final current = _selectedLabId;

    if (current != null &&
        assignedLaboratories.any((laboratory) => laboratory.id == current)) {
      return current;
    }

    return assignedLaboratories.first.id;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F9EF),

      appBar: AppBar(
        leading: BackButton(
          onPressed: () => popOrGo(context, '/lab-admin/assets'),
        ),
        backgroundColor: const Color(0xFFF6F9EF),

        surfaceTintColor: Colors.transparent,

        elevation: 0,

        title: const Text(
          'Tambah Aset',

          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),

      body: StreamBuilder<List<LabMembership>>(
        stream: _membershipService.watchCurrentLabAdminMemberships(),

        builder: (context, membershipSnapshot) {
          if (membershipSnapshot.connectionState == ConnectionState.waiting &&
              !membershipSnapshot.hasData) {
            return const LabFlowLoadingState(
              title: 'Memuat akses laboratorium',

              message:
                  'Memeriksa laboratorium yang menjadi tanggung jawab Anda.',
            );
          }

          if (membershipSnapshot.hasError) {
            return const LabFlowConnectionErrorState(
              title: 'Akses laboratorium tidak dapat dimuat',

              message:
                  'Assignment laboratorium tidak dapat diperiksa saat ini. '
                  'Periksa koneksi Anda lalu coba lagi.',
            );
          }

          final memberships = membershipSnapshot.data ?? <LabMembership>[];

          if (memberships.isEmpty) {
            return _buildNoMembershipState();
          }

          return StreamBuilder<List<Laboratory>>(
            stream: _membershipService.watchActiveLaboratories(),

            builder: (context, laboratorySnapshot) {
              if (laboratorySnapshot.connectionState ==
                      ConnectionState.waiting &&
                  !laboratorySnapshot.hasData) {
                return const LabFlowLoadingState(
                  title: 'Memuat laboratorium',

                  message: 'Menyiapkan laboratorium yang dapat menerima aset.',
                );
              }

              if (laboratorySnapshot.hasError) {
                return const LabFlowConnectionErrorState(
                  title: 'Laboratorium tidak dapat dimuat',

                  message:
                      'Data laboratorium tidak dapat diambil saat ini. '
                      'Periksa koneksi Anda lalu coba lagi.',
                );
              }

              final laboratories = laboratorySnapshot.data ?? <Laboratory>[];

              final membershipLabIds = memberships
                  .map((membership) => membership.labId)
                  .toSet();

              final assignedLaboratories = laboratories
                  .where(
                    (laboratory) => membershipLabIds.contains(laboratory.id),
                  )
                  .toList();

              assignedLaboratories.sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
              );

              if (assignedLaboratories.isEmpty) {
                return _buildNoActiveLaboratoryState();
              }

              final selectedLabId = _resolveSelectedLabId(assignedLaboratories);

              return _buildForm(
                laboratories: assignedLaboratories,

                selectedLabId: selectedLabId,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildForm({
    required List<Laboratory> laboratories,

    required String selectedLabId,
  }) {
    final selectedLaboratory = laboratories.firstWhere(
      (laboratory) => laboratory.id == selectedLabId,
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),

        child: Form(
          key: _formKey,

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              _buildLaboratoryField(
                laboratories: laboratories,
                selectedLaboratory: selectedLaboratory,
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
                              'Draft lokal aset dimuat',
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

              const SizedBox(height: 16),

              _buildAssetImageField(),

              const SizedBox(height: 16),

              TextFormField(
                controller: _nameController,

                validator: _requiredValidator,

                enabled: !_isLoading,

                textInputAction: TextInputAction.next,

                decoration: _inputDecoration(
                  'Nama Aset',

                  'Laptop Praktikum 01',

                  Icons.inventory_2_outlined,
                ),
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _codeController,

                validator: _requiredValidator,

                enabled: !_isLoading,

                textCapitalization: TextCapitalization.characters,

                textInputAction: TextInputAction.next,

                autocorrect: false,

                decoration: _inputDecoration(
                  'Kode Aset',

                  'IOT-LTP-001',

                  Icons.qr_code_rounded,
                ),
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _categoryController,

                validator: _requiredValidator,

                enabled: !_isLoading,

                textInputAction: TextInputAction.next,

                decoration: _inputDecoration(
                  'Kategori',

                  'Laptop',

                  Icons.category_outlined,
                ),
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _stockController,

                validator: _stockValidator,

                enabled: !_isLoading,

                keyboardType: TextInputType.number,

                textInputAction: TextInputAction.next,

                decoration: _inputDecoration(
                  'Stock',

                  '1',

                  Icons.numbers_rounded,
                ),
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _locationController,

                validator: _requiredValidator,

                enabled: !_isLoading,

                textInputAction: TextInputAction.next,

                decoration: _inputDecoration(
                  'Lokasi Aset',

                  'Rak A · Meja 01',

                  Icons.location_on_outlined,
                ),
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _descriptionController,

                enabled: !_isLoading,

                maxLines: 4,

                textInputAction: TextInputAction.newline,

                decoration: _inputDecoration(
                  'Deskripsi',

                  'Aset untuk kegiatan praktikum...',

                  Icons.notes_rounded,
                ),
              ),

              const SizedBox(height: 24),

              const Text(
                'Kondisi Aset',

                style: TextStyle(
                  fontSize: 13,

                  fontWeight: FontWeight.w700,

                  color: Color(0xFF6B7280),
                ),
              ),

              const SizedBox(height: 8),

              SizedBox(
                width: double.infinity,

                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment<String>(
                      value: 'good',

                      label: Text('Baik'),

                      icon: Icon(Icons.check_circle_outline_rounded),
                    ),

                    ButtonSegment<String>(
                      value: 'minor_damage',

                      label: Text('Ringan'),

                      icon: Icon(Icons.build_outlined),
                    ),

                    ButtonSegment<String>(
                      value: 'damaged',

                      label: Text('Rusak'),

                      icon: Icon(Icons.report_problem_outlined),
                    ),
                  ],

                  selected: {_condition},

                  onSelectionChanged: _isLoading
                      ? null
                      : (selection) {
                          setState(() {
                            _condition = selection.first;
                          });
                        },
                ),
              ),

              const SizedBox(height: 20),

              _buildAutomaticInformation(),

              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,

                height: 54,

                child: FilledButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          _save(selectedLabId);
                        },

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
                            Icon(Icons.add_box_outlined, size: 20),

                            SizedBox(width: 10),

                            Text(
                              'Simpan Aset',

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
                  onPressed: _isLoading
                      ? null
                      : () => _saveDraftLocally(selectedLabId),
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
    );
  }

  Widget _buildAssetImageField() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE2D5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.image_outlined, color: Color(0xFF5F6672)),
              SizedBox(width: 10),
              Text(
                'Foto Aset',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _selectedImage == null
                ? 'Belum ada foto yang dipilih.'
                : _selectedImage!.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : _pickImage,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(
                    _selectedImage == null ? 'Pilih Foto' : 'Ganti Foto',
                  ),
                ),
              ),
              if (_selectedImage != null) ...[
                const SizedBox(width: 10),
                IconButton(
                  tooltip: 'Hapus foto',
                  onPressed: _isLoading
                      ? null
                      : () {
                          setState(() {
                            _selectedImage = null;
                          });
                        },
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'JPG, JPEG, PNG, atau WEBP. Maksimal 5 MB.',
            style: TextStyle(fontSize: 12, color: Color(0xFF7A8190)),
          ),
        ],
      ),
    );
  }

  Widget _buildLaboratoryField({
    required List<Laboratory> laboratories,

    required Laboratory selectedLaboratory,
  }) {
    if (laboratories.length == 1) {
      return Container(
        width: double.infinity,

        padding: const EdgeInsets.all(16),

        decoration: BoxDecoration(
          color: Colors.white,

          borderRadius: BorderRadius.circular(18),

          border: Border.all(color: const Color(0xFFDDE2D5)),
        ),

        child: Row(
          children: [
            const Icon(Icons.science_outlined, color: Color(0xFF5F6672)),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  const Text(
                    'Laboratorium',

                    style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  ),

                  const SizedBox(height: 3),

                  Text(
                    selectedLaboratory.name,

                    style: const TextStyle(
                      fontSize: 15,

                      fontWeight: FontWeight.w700,

                      color: Color(0xFF111111),
                    ),
                  ),

                  const SizedBox(height: 2),

                  Text(
                    '${selectedLaboratory.code} · '
                    '${selectedLaboratory.location}',

                    style: const TextStyle(
                      fontSize: 12,

                      color: Color(0xFF7A8190),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return DropdownButtonFormField<String>(
      initialValue: selectedLaboratory.id,

      decoration: _inputDecoration(
        'Laboratorium',

        'Pilih laboratorium',

        Icons.science_outlined,
      ),

      items: laboratories.map((laboratory) {
        return DropdownMenuItem<String>(
          value: laboratory.id,

          child: Text(
            '${laboratory.code} · ${laboratory.name}',

            maxLines: 1,

            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),

      onChanged: _isLoading
          ? null
          : (value) {
              if (value == null) {
                return;
              }

              setState(() {
                _selectedLabId = value;
              });
            },
    );
  }

  Widget _buildAutomaticInformation() {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: const Color(0xFFEAFBCB),

        borderRadius: BorderRadius.circular(18),
      ),

      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Icon(Icons.auto_awesome_outlined, color: Color(0xFF111111)),

          SizedBox(width: 12),

          Expanded(
            child: Text(
              'Status awal aset akan otomatis menjadi Available. '
              'Identitas QR juga dibuat otomatis setelah aset disimpan.',

              style: TextStyle(
                fontSize: 13,

                height: 1.45,

                fontWeight: FontWeight.w600,

                color: Color(0xFF111111),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoMembershipState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),

        child: Column(
          mainAxisSize: MainAxisSize.min,

          children: [
            Icon(
              Icons.assignment_late_outlined,

              size: 60,

              color: Color(0xFF6B7280),
            ),

            SizedBox(height: 18),

            Text(
              'Belum ada assignment',

              textAlign: TextAlign.center,

              style: TextStyle(
                fontSize: 21,

                fontWeight: FontWeight.w800,

                color: Color(0xFF111111),
              ),
            ),

            SizedBox(height: 8),

            Text(
              'Akun Lab Admin ini belum memiliki akses aktif '
              'ke laboratorium mana pun.',

              textAlign: TextAlign.center,

              style: TextStyle(
                fontSize: 14,

                height: 1.45,

                color: Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoActiveLaboratoryState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),

        child: Column(
          mainAxisSize: MainAxisSize.min,

          children: [
            Icon(Icons.science_outlined, size: 60, color: Color(0xFF6B7280)),

            SizedBox(height: 18),

            Text(
              'Laboratorium tidak tersedia',

              textAlign: TextAlign.center,

              style: TextStyle(
                fontSize: 21,

                fontWeight: FontWeight.w800,

                color: Color(0xFF111111),
              ),
            ),

            SizedBox(height: 8),

            Text(
              'Assignment ditemukan, tetapi tidak ada '
              'laboratorium aktif yang dapat menerima aset.',

              textAlign: TextAlign.center,

              style: TextStyle(
                fontSize: 14,

                height: 1.45,

                color: Color(0xFF6B7280),
              ),
            ),
          ],
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

      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),

      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),

        borderSide: const BorderSide(color: Color(0xFFD8DDD0)),
      ),

      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),

        borderSide: const BorderSide(color: Color(0xFF111111), width: 1.4),
      ),

      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),

        borderSide: const BorderSide(color: Color(0xFFD8DDD0)),
      ),

      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),

        borderSide: const BorderSide(color: Color(0xFFBD3232)),
      ),

      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),

        borderSide: const BorderSide(color: Color(0xFFBD3232), width: 1.4),
      ),
    );
  }
}
