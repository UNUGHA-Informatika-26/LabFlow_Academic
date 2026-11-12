import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/connectivity/connectivity_service.dart';
import '../../asset/data/asset_image_service.dart';
import '../../auth/data/auth_service.dart';
import '../../auth/domain/user_profile.dart';

abstract class ProfileEditor {
  Future<UserProfile> load();
  Future<UserProfile> saveProfile({
    required String fullName,
    required String phoneNumber,
    required String nim,
    required String studyProgram,
    required int? semester,
    required String nip,
    required String nidn,
    XFile? photo,
    bool removePhoto = false,
  });
}

class ProfileEditService implements ProfileEditor {
  ProfileEditService({
    AuthService? authService,
    FirebaseFirestore? firestore,
    AssetImageService? images,
    ConnectivityService? connectivity,
  }) : _authService = authService ?? AuthService(),
       _firestore = firestore ?? FirebaseFirestore.instance,
       _imagesOverride = images,
       _connectivityOverride = connectivity;

  final AuthService _authService;
  final FirebaseFirestore _firestore;
  final AssetImageService? _imagesOverride;
  final ConnectivityService? _connectivityOverride;

  AssetImageService get _images => _imagesOverride ?? AssetImageService();
  ConnectivityService get _connectivity =>
      _connectivityOverride ?? PluginConnectivityService();

  static String? validateFullName(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return 'Nama lengkap wajib diisi.';
    if (clean.length > 100) return 'Nama lengkap maksimal 100 karakter.';
    return null;
  }

  static String? validatePhoneNumber(String value) =>
      value.trim().length > 20 ? 'Nomor HP maksimal 20 karakter.' : null;

  static String? validateRoleFields({
    required UserProfile? profile,
    required String nim,
    required String studyProgram,
    required int? semester,
    required String nip,
    required String nidn,
  }) {
    if (profile == null) return 'Profil tidak ditemukan.';
    String? optionalText(String value, String label, int maximum) {
      final clean = value.trim();
      if (clean.isNotEmpty && clean.length > maximum) {
        return '$label maksimal $maximum karakter.';
      }
      return null;
    }

    if (profile.isStudent) {
      return optionalText(nim, 'NIM', 30) ??
          optionalText(studyProgram, 'Program studi', 100) ??
          (semester != null && (semester < 1 || semester > 14)
              ? 'Semester harus antara 1 dan 14.'
              : null);
    }
    if (profile.isLabAdmin) {
      return optionalText(nip, 'NIP', 30) ?? optionalText(nidn, 'NIDN', 30);
    }
    return null;
  }

  @override
  Future<UserProfile> load() => _authService.getCurrentUserProfile();

  @override
  Future<UserProfile> saveProfile({
    required String fullName,
    required String phoneNumber,
    required String nim,
    required String studyProgram,
    required int? semester,
    required String nip,
    required String nidn,
    XFile? photo,
    bool removePhoto = false,
  }) async {
    final error = validateFullName(fullName);
    if (error != null) throw ProfileEditException(error);
    final phoneError = validatePhoneNumber(phoneNumber);
    if (phoneError != null) throw ProfileEditException(phoneError);

    final profile = await load();
    final roleError = validateRoleFields(
      profile: profile,
      nim: nim,
      studyProgram: studyProgram,
      semester: semester,
      nip: nip,
      nidn: nidn,
    );
    if (roleError != null) throw ProfileEditException(roleError);

    final uid = _authService.currentUser?.uid;
    if (uid == null) {
      throw const ProfileEditException('Sesi login tidak ditemukan.');
    }

    try {
      final update = <String, Object?>{
        'fullName': fullName.trim(),
        'phoneNumber': phoneNumber.trim().isEmpty ? null : phoneNumber.trim(),
      };
      if (profile.isStudent) {
        update.addAll({
          'nim': nim.trim().isEmpty ? null : nim.trim(),
          'studyProgram': studyProgram.trim().isEmpty
              ? null
              : studyProgram.trim(),
          'semester': semester,
        });
      } else if (profile.isLabAdmin) {
        update.addAll({
          'nip': nip.trim().isEmpty ? null : nip.trim(),
          'nidn': nidn.trim().isEmpty ? null : nidn.trim(),
        });
      }
      if (photo != null) {
        if (!await _connectivity.hasNetworkInterface()) {
          throw const ProfileEditException(
            'Foto membutuhkan koneksi internet.',
          );
        }
        update['profilePhotoUrl'] = (await _images.uploadImage(
          image: photo,
          folder: 'labflow/profiles/$uid',
          maximumBytes: 5 * 1024 * 1024,
        )).secureUrl;
      } else if (removePhoto) {
        update['profilePhotoUrl'] = null;
      }
      String normalize(Object? value) => value is String ? value.trim() : '';
      final photoChanged =
          update.containsKey('profilePhotoUrl') &&
          normalize(profile.profilePhotoUrl) !=
              normalize(update['profilePhotoUrl']);
      final changed =
          normalize(profile.fullName) != normalize(update['fullName']) ||
          normalize(profile.phoneNumber) != normalize(update['phoneNumber']) ||
          (profile.isStudent &&
              (normalize(profile.nim) != normalize(update['nim']) ||
                  normalize(profile.studyProgram) !=
                      normalize(update['studyProgram']) ||
                  profile.semester != update['semester'])) ||
          (profile.isLabAdmin &&
              (normalize(profile.nip) != normalize(update['nip']) ||
                  normalize(profile.nidn) != normalize(update['nidn']))) ||
          photoChanged;
      if (!changed) return profile;
      final currentValues = <String, Object?>{
        'fullName': profile.fullName,
        'phoneNumber': profile.phoneNumber,
        'nim': profile.nim,
        'studyProgram': profile.studyProgram,
        'semester': profile.semester,
        'nip': profile.nip,
        'nidn': profile.nidn,
        'profilePhotoUrl': profile.profilePhotoUrl,
      };
      update.removeWhere(
        (key, value) =>
            currentValues.containsKey(key) &&
            (key == 'semester'
                ? currentValues[key] == value
                : normalize(currentValues[key]) == normalize(value)),
      );
      await _firestore.collection('users').doc(uid).update(update);
      return await _authService.getCurrentUserProfile(forceRefresh: true);
    } on AssetImageException catch (error) {
      throw ProfileEditException(error.message);
    } on FirebaseException catch (exception) {
      if (exception.code == 'permission-denied') {
        throw const ProfileEditException(
          'Firestore menolak perubahan profil. Periksa Rules aktif dan hak edit akun.',
        );
      }
      if (exception.code == 'unavailable' ||
          exception.code == 'deadline-exceeded') {
        throw const ProfileEditException(
          'Tidak dapat terhubung ke Firestore. Periksa koneksi dan coba lagi.',
        );
      }
      throw const ProfileEditException(
        'Profil tidak dapat disimpan. Periksa koneksi dan coba lagi.',
      );
    }
  }
}

class ProfileEditException implements Exception {
  const ProfileEditException(this.message);
  final String message;
}
