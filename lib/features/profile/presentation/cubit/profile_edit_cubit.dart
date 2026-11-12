import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../auth/domain/user_profile.dart';
import '../../data/profile_edit_service.dart';

enum ProfileEditStatus { loading, editing, saving, success, failure }

class ProfileEditState {
  const ProfileEditState({
    this.status = ProfileEditStatus.loading,
    this.profile,
    this.fullName = '',
    this.phoneNumber = '',
    this.nim = '',
    this.studyProgram = '',
    this.semester,
    this.nip = '',
    this.nidn = '',
    this.photoUrl,
    this.photo,
    this.removePhoto = false,
    this.errorMessage = '',
  });

  final ProfileEditStatus status;
  final UserProfile? profile;
  final String fullName;
  final String phoneNumber;
  final String nim;
  final String studyProgram;
  final int? semester;
  final String nip;
  final String nidn;
  final String? photoUrl;
  final XFile? photo;
  final bool removePhoto;
  final String errorMessage;

  bool get hasChanges {
    final p = profile;
    if (p == null) return false;
    String norm(String? value) => value?.trim() ?? '';
    final currentPhotoUrl = norm(p.profilePhotoUrl);
    final photoChanged =
        photo != null || (removePhoto && currentPhotoUrl.isNotEmpty);
    return norm(p.fullName) != norm(fullName) ||
        norm(p.phoneNumber) != norm(phoneNumber) ||
        (p.isStudent &&
            (norm(p.nim) != norm(nim) ||
                norm(p.studyProgram) != norm(studyProgram) ||
                p.semester != semester)) ||
        (p.isLabAdmin &&
            (norm(p.nip) != norm(nip) || norm(p.nidn) != norm(nidn))) ||
        photoChanged;
  }
}

class ProfileEditCubit extends Cubit<ProfileEditState> {
  ProfileEditCubit(this._service) : super(const ProfileEditState());

  final ProfileEditor _service;

  Future<void> load() async {
    emit(const ProfileEditState());
    try {
      final profile = await _service.load();
      emit(
        ProfileEditState(
          status: ProfileEditStatus.editing,
          profile: profile,
          fullName: profile.fullName,
          phoneNumber: profile.phoneNumber ?? '',
          nim: profile.nim ?? '',
          studyProgram: profile.studyProgram ?? '',
          semester: profile.semester,
          nip: profile.nip ?? '',
          nidn: profile.nidn ?? '',
          photoUrl: profile.profilePhotoUrl,
        ),
      );
    } catch (_) {
      emit(
        const ProfileEditState(
          status: ProfileEditStatus.failure,
          errorMessage: 'Profil tidak dapat dimuat. Coba lagi.',
        ),
      );
    }
  }

  void setPhoneNumber(String value) => _edit(phoneNumber: value);
  void setNim(String value) => _edit(nim: value);
  void setStudyProgram(String value) => _edit(studyProgram: value);
  void setSemester(int? value) => _edit(semester: value, clearSemester: true);
  void setNip(String value) => _edit(nip: value);
  void setNidn(String value) => _edit(nidn: value);
  void setPhoto(XFile? value) => _edit(photo: value, removePhoto: false);
  void removeProfilePhoto() {
    if (state.profile == null || state.status == ProfileEditStatus.saving) {
      return;
    }
    emit(
      ProfileEditState(
        status: ProfileEditStatus.editing,
        profile: state.profile,
        fullName: state.fullName,
        phoneNumber: state.phoneNumber,
        nim: state.nim,
        studyProgram: state.studyProgram,
        semester: state.semester,
        nip: state.nip,
        nidn: state.nidn,
        photoUrl: state.photoUrl,
        removePhoto: true,
      ),
    );
  }

  void _edit({
    String? phoneNumber,
    String? nim,
    String? studyProgram,
    int? semester,
    bool clearSemester = false,
    String? nip,
    String? nidn,
    XFile? photo,
    bool? removePhoto,
  }) {
    if (state.profile == null || state.status == ProfileEditStatus.saving) {
      return;
    }
    emit(
      ProfileEditState(
        status: ProfileEditStatus.editing,
        profile: state.profile,
        fullName: state.fullName,
        phoneNumber: phoneNumber ?? state.phoneNumber,
        nim: nim ?? state.nim,
        studyProgram: studyProgram ?? state.studyProgram,
        semester: clearSemester ? semester : (semester ?? state.semester),
        nip: nip ?? state.nip,
        nidn: nidn ?? state.nidn,
        photoUrl: state.photoUrl,
        photo: photo ?? state.photo,
        removePhoto: removePhoto ?? state.removePhoto,
      ),
    );
  }

  void setFullName(String value) {
    if (state.profile == null || state.status == ProfileEditStatus.saving) {
      return;
    }
    emit(
      ProfileEditState(
        status: ProfileEditStatus.editing,
        profile: state.profile,
        fullName: value,
        phoneNumber: state.phoneNumber,
        nim: state.nim,
        studyProgram: state.studyProgram,
        semester: state.semester,
        nip: state.nip,
        nidn: state.nidn,
        photoUrl: state.photoUrl,
        photo: state.photo,
        removePhoto: state.removePhoto,
      ),
    );
  }

  Future<void> save() async {
    if (state.profile == null || state.status == ProfileEditStatus.saving) {
      return;
    }
    final current = state;
    final error =
        ProfileEditService.validateFullName(current.fullName) ??
        ProfileEditService.validatePhoneNumber(current.phoneNumber) ??
        ProfileEditService.validateRoleFields(
          profile: current.profile,
          nim: current.nim,
          studyProgram: current.studyProgram,
          semester: current.semester,
          nip: current.nip,
          nidn: current.nidn,
        );
    if (error != null) {
      emit(
        ProfileEditState(
          status: ProfileEditStatus.editing,
          profile: current.profile,
          fullName: current.fullName,
          phoneNumber: current.phoneNumber,
          nim: current.nim,
          studyProgram: current.studyProgram,
          semester: current.semester,
          nip: current.nip,
          nidn: current.nidn,
          photoUrl: current.photoUrl,
          photo: current.photo,
          removePhoto: current.removePhoto,
          errorMessage: error,
        ),
      );
      return;
    }
    if (!current.hasChanges) {
      return;
    }

    emit(
      ProfileEditState(
        status: ProfileEditStatus.saving,
        profile: current.profile,
        fullName: current.fullName,
        phoneNumber: current.phoneNumber,
        nim: current.nim,
        studyProgram: current.studyProgram,
        semester: current.semester,
        nip: current.nip,
        nidn: current.nidn,
        photoUrl: current.photoUrl,
        photo: current.photo,
        removePhoto: current.removePhoto,
      ),
    );
    try {
      final profile = await _service.saveProfile(
        fullName: current.fullName,
        phoneNumber: current.phoneNumber,
        nim: current.nim,
        studyProgram: current.studyProgram,
        semester: current.semester,
        nip: current.nip,
        nidn: current.nidn,
        photo: current.photo,
        removePhoto: current.removePhoto,
      );
      emit(
        ProfileEditState(
          status: ProfileEditStatus.success,
          profile: profile,
          fullName: profile.fullName,
          phoneNumber: profile.phoneNumber ?? '',
          nim: profile.nim ?? '',
          studyProgram: profile.studyProgram ?? '',
          semester: profile.semester,
          nip: profile.nip ?? '',
          nidn: profile.nidn ?? '',
          photoUrl: profile.profilePhotoUrl,
        ),
      );
    } on ProfileEditException catch (exception) {
      emit(
        ProfileEditState(
          status: ProfileEditStatus.failure,
          profile: current.profile,
          fullName: current.fullName,
          phoneNumber: current.phoneNumber,
          nim: current.nim,
          studyProgram: current.studyProgram,
          semester: current.semester,
          nip: current.nip,
          nidn: current.nidn,
          photoUrl: current.photoUrl,
          photo: current.photo,
          removePhoto: current.removePhoto,
          errorMessage: exception.message,
        ),
      );
    } catch (_) {
      emit(
        ProfileEditState(
          status: ProfileEditStatus.failure,
          profile: current.profile,
          fullName: current.fullName,
          phoneNumber: current.phoneNumber,
          nim: current.nim,
          studyProgram: current.studyProgram,
          semester: current.semester,
          nip: current.nip,
          nidn: current.nidn,
          photoUrl: current.photoUrl,
          photo: current.photo,
          removePhoto: current.removePhoto,
          errorMessage: 'Profil tidak dapat disimpan. Coba lagi.',
        ),
      );
    }
  }
}
