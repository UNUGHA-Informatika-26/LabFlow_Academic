import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../shared/presentation/notifications/labflow_notification.dart';
import '../../data/profile_edit_service.dart';
import '../cubit/profile_edit_cubit.dart';

class ProfileEditPage extends StatelessWidget {
  const ProfileEditPage({required this.returnPath, this.editor, super.key});

  final String returnPath;
  final ProfileEditor? editor;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => ProfileEditCubit(editor ?? ProfileEditService())..load(),
    child: _ProfileEditView(returnPath: returnPath),
  );
}

class _ProfileEditView extends StatefulWidget {
  const _ProfileEditView({required this.returnPath});

  final String returnPath;

  @override
  State<_ProfileEditView> createState() => _ProfileEditViewState();
}

class _ProfileEditViewState extends State<_ProfileEditView> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _nimController = TextEditingController();
  final TextEditingController _programController = TextEditingController();
  final TextEditingController _nipController = TextEditingController();
  final TextEditingController _nidnController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  bool _initialized = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _nimController.dispose();
    _programController.dispose();
    _nipController.dispose();
    _nidnController.dispose();
    super.dispose();
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(widget.returnPath);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: context.canPop(),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !context.canPop()) context.go(widget.returnPath);
    },
    child: BlocConsumer<ProfileEditCubit, ProfileEditState>(
      listener: (context, state) {
        if (state.profile != null && !_initialized) {
          _initialized = true;
          _nameController.text = state.profile!.fullName;
          _phoneController.text = state.profile!.phoneNumber ?? '';
          _nimController.text = state.profile!.nim ?? '';
          _programController.text = state.profile!.studyProgram ?? '';
          _nipController.text = state.profile!.nip ?? '';
          _nidnController.text = state.profile!.nidn ?? '';
        }
        if (state.status == ProfileEditStatus.failure &&
            state.errorMessage.isNotEmpty) {
          showLabFlowNotification(
            context: context,
            message: state.errorMessage,
            type: LabFlowNotificationType.error,
          );
        }
        if (state.status == ProfileEditStatus.success) {
          if (context.canPop()) {
            context.pop(true);
          } else {
            context.go(widget.returnPath);
          }
        }
      },
      builder: (context, state) => Scaffold(
        backgroundColor: const Color(0xFFF6F9EF),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF6F9EF),
          title: const Text(
            'Edit Profil',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          leading: IconButton(
            tooltip: 'Kembali',
            onPressed: _back,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        body: SafeArea(
          child: switch (state.status) {
            ProfileEditStatus.loading => const Center(
              child: CircularProgressIndicator(),
            ),
            ProfileEditStatus.failure when state.profile == null => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.errorMessage),
                  TextButton(
                    onPressed: context.read<ProfileEditCubit>().load,
                    child: const Text('Coba lagi'),
                  ),
                ],
              ),
            ),
            _ => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                Center(
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: state.status == ProfileEditStatus.saving
                            ? null
                            : _choosePhoto,
                        child: CircleAvatar(
                          radius: 48,
                          backgroundColor: const Color(0xFFE2F0B9),
                          backgroundImage: state.photo != null
                              ? FileImage(File(state.photo!.path))
                              : !state.removePhoto && state.photoUrl != null
                              ? NetworkImage(state.photoUrl!) as ImageProvider
                              : null,
                          child:
                              state.photo == null &&
                                  (state.photoUrl == null || state.removePhoto)
                              ? Text(_initials(state.fullName))
                              : null,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: state.status == ProfileEditStatus.saving
                            ? null
                            : _choosePhoto,
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Ubah foto'),
                      ),
                      if (state.photoUrl != null || state.photo != null)
                        TextButton(
                          onPressed: state.status == ProfileEditStatus.saving
                              ? null
                              : context
                                    .read<ProfileEditCubit>()
                                    .removeProfilePhoto,
                          child: const Text('Hapus foto'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _fieldLabel('Nama Lengkap'),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  maxLength: 100,
                  textCapitalization: TextCapitalization.words,
                  enabled: state.status != ProfileEditStatus.saving,
                  onChanged: context.read<ProfileEditCubit>().setFullName,
                  decoration: _inputDecoration('Masukkan nama lengkap'),
                ),
                const SizedBox(height: 8),
                _fieldLabel('Nomor HP'),
                const SizedBox(height: 8),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  maxLength: 20,
                  enabled: state.status != ProfileEditStatus.saving,
                  onChanged: context.read<ProfileEditCubit>().setPhoneNumber,
                  decoration: const InputDecoration(
                    labelText: 'Nomor HP (opsional)',
                  ),
                ),
                if (state.profile?.isStudent == true) ...[
                  _fieldLabel('NIM'),
                  TextField(
                    controller: _nimController,
                    maxLength: 30,
                    enabled: state.status != ProfileEditStatus.saving,
                    onChanged: context.read<ProfileEditCubit>().setNim,
                    decoration: _inputDecoration('Masukkan NIM'),
                  ),
                  _fieldLabel('Program Studi'),
                  TextField(
                    controller: _programController,
                    maxLength: 100,
                    textCapitalization: TextCapitalization.words,
                    enabled: state.status != ProfileEditStatus.saving,
                    onChanged: context.read<ProfileEditCubit>().setStudyProgram,
                    decoration: _inputDecoration('Masukkan program studi'),
                  ),
                  _fieldLabel('Semester'),
                  DropdownButtonFormField<int>(
                    initialValue: state.semester,
                    decoration: _inputDecoration('Pilih semester'),
                    items: List.generate(14, (index) => index + 1)
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text('Semester $value'),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: state.status == ProfileEditStatus.saving
                        ? null
                        : context.read<ProfileEditCubit>().setSemester,
                  ),
                ],
                if (state.profile?.isLabAdmin == true) ...[
                  _fieldLabel('NIP'),
                  TextField(
                    controller: _nipController,
                    maxLength: 30,
                    enabled: state.status != ProfileEditStatus.saving,
                    onChanged: context.read<ProfileEditCubit>().setNip,
                    decoration: _inputDecoration('Masukkan NIP'),
                  ),
                  _fieldLabel('NIDN'),
                  TextField(
                    controller: _nidnController,
                    maxLength: 30,
                    enabled: state.status != ProfileEditStatus.saving,
                    onChanged: context.read<ProfileEditCubit>().setNidn,
                    decoration: _inputDecoration('Masukkan NIDN'),
                  ),
                ],
                if (state.errorMessage.isNotEmpty)
                  Text(
                    state.errorMessage,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFFB42318),
                    ),
                  ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed:
                      state.status == ProfileEditStatus.saving ||
                          !state.hasChanges
                      ? null
                      : context.read<ProfileEditCubit>().save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: const Color(0xFF111111),
                  ),
                  child: state.status == ProfileEditStatus.saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Simpan Perubahan',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
                if (!state.hasChanges)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Center(
                      child: Text(
                        'Belum ada perubahan untuk disimpan.',
                        style: TextStyle(color: Color(0xFF6B7280)),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                const Text(
                  'Email, role, status, UID, dan assignment laboratorium '
                  'dikelola administrator.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: Color(0xFF6B7280),
                  ),
                ),
                ],
              ),
            ),
          },
        ),
      ),
    ),
  );

  Future<void> _choosePhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              title: const Text('Ambil Foto'),
              leading: const Icon(Icons.camera_alt),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              title: const Text('Pilih dari Galeri'),
              leading: const Icon(Icons.photo_library),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final photo = await _picker.pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 512,
        maxHeight: 512,
        requestFullMetadata: false,
      );
      if (mounted && photo != null) {
        context.read<ProfileEditCubit>().setPhoto(photo);
      }
    } catch (_) {
      if (mounted) {
        showLabFlowNotification(
          context: context,
          message: 'Foto tidak dapat dipilih.',
          type: LabFlowNotificationType.error,
        );
      }
    }
  }

  Widget _fieldLabel(String value) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 8),
    child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
  );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
  );

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    return parts.length == 1
        ? parts.first.substring(0, 1).toUpperCase()
        : '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}
