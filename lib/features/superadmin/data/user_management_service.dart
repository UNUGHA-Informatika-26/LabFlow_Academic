import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../../firebase_options.dart';
import '../../auth/domain/user_profile.dart';
import 'admin_credential_service.dart';

/// Service khusus Superadmin untuk mengelola pengguna LabFlow.
class UserManagementService {
  UserManagementService({
    FirebaseFirestore? firestore,
    FirebaseAuth? firebaseAuth,
    AdminCredentialService? credentialService,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _credentialService =
           credentialService ??
           AdminCredentialService(
             firebaseAuth: firebaseAuth ?? FirebaseAuth.instance,
           );

  final FirebaseFirestore _firestore;
  final FirebaseAuth _firebaseAuth;
  final AdminCredentialService _credentialService;

  /// Mengambil seluruh pengguna secara realtime.
  Stream<List<UserProfile>> watchUsers() {
    return _firestore.collection('users').snapshots().map((snapshot) {
      final users = snapshot.docs.map(UserProfile.fromDocument).toList();

      users.sort(
        (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
      );

      return users;
    });
  }

  /// Mengambil satu pengguna berdasarkan UID.
  Future<UserProfile> getUser(String userId) async {
    final document = await _firestore.collection('users').doc(userId).get();

    if (!document.exists) {
      throw const UserManagementException('Pengguna tidak ditemukan.');
    }

    return UserProfile.fromDocument(document);
  }

  /// Membuat akun baru tanpa mengganti session Superadmin.
  Future<UserProfile> createUser({
    required String fullName,
    required String email,
    required String password,
    required String role,
    required String status,
    String phoneNumber = '',
    String nim = '',
    String studyProgram = '',
    int? semester,
    String nip = '',
    String nidn = '',
  }) async {
    final cleanName = fullName.trim();
    final cleanEmail = email.trim().toLowerCase();

    _validateProfile(fullName: cleanName, role: role, status: status);
    _validateIdentity(
      phoneNumber: phoneNumber,
      nim: nim,
      studyProgram: studyProgram,
      semester: semester,
      nip: nip,
      nidn: nidn,
    );

    FirebaseApp? secondaryApp;
    FirebaseAuth? secondaryAuth;
    User? createdAuthUser;

    try {
      final secondaryAppName =
          'user-provisioning-${DateTime.now().microsecondsSinceEpoch}';

      secondaryApp = await Firebase.initializeApp(
        name: secondaryAppName,
        options: DefaultFirebaseOptions.currentPlatform,
      );

      secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);

      final credential = await secondaryAuth.createUserWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );

      createdAuthUser = credential.user;

      if (createdAuthUser == null) {
        throw const UserManagementException(
          'Firebase tidak mengembalikan data akun baru.',
        );
      }

      final uid = createdAuthUser.uid;

      await _firestore.collection('users').doc(uid).set({
        'uid': uid,
        'email': cleanEmail,
        'fullName': cleanName,
        'role': role,
        'status': status,
        'phoneNumber': phoneNumber.trim().isEmpty ? null : phoneNumber.trim(),
        if (role == 'student') ...{
          'nim': nim.trim().isEmpty ? null : nim.trim(),
          'studyProgram': studyProgram.trim().isEmpty
              ? null
              : studyProgram.trim(),
          'semester': semester,
        },
        if (role == 'lab_admin') ...{
          'nip': nip.trim().isEmpty ? null : nip.trim(),
          'nidn': nidn.trim().isEmpty ? null : nidn.trim(),
        },
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return UserProfile(
        uid: uid,
        email: cleanEmail,
        fullName: cleanName,
        role: role,
        status: status,
        phoneNumber: phoneNumber.trim().isEmpty ? null : phoneNumber.trim(),
        nim: role == 'student' && nim.trim().isNotEmpty ? nim.trim() : null,
        studyProgram: role == 'student' && studyProgram.trim().isNotEmpty
            ? studyProgram.trim()
            : null,
        semester: role == 'student' ? semester : null,
        nip: role == 'lab_admin' && nip.trim().isNotEmpty ? nip.trim() : null,
        nidn: role == 'lab_admin' && nidn.trim().isNotEmpty
            ? nidn.trim()
            : null,
      );
    } on FirebaseAuthException catch (error) {
      throw UserManagementException(_firebaseAuthMessage(error.code));
    } on FirebaseException catch (error) {
      if (createdAuthUser != null) {
        try {
          await createdAuthUser.delete();
        } catch (_) {
          // Cleanup best-effort.
        }
      }

      throw UserManagementException(
        'Gagal menyimpan profil pengguna: '
        '${error.message ?? error.code}',
      );
    } on UserManagementException {
      rethrow;
    } catch (_) {
      if (createdAuthUser != null) {
        try {
          await createdAuthUser.delete();
        } catch (_) {
          // Cleanup best-effort.
        }
      }

      throw const UserManagementException(
        'Terjadi kesalahan saat membuat pengguna.',
      );
    } finally {
      if (secondaryAuth != null) {
        try {
          await secondaryAuth.signOut();
        } catch (_) {
          // Cleanup best-effort.
        }
      }

      if (secondaryApp != null) {
        try {
          await secondaryApp.delete();
        } catch (_) {
          // Cleanup best-effort.
        }
      }
    }
  }

  /// Memperbarui profile pengguna.
  ///
  /// Email sengaja tidak ikut diperbarui karena email juga
  /// tersimpan pada Firebase Authentication.
  /// Mengembalikan `true` jika ada field yang benar-benar berubah dan disimpan.
  Future<bool> updateUser({
    required String userId,
    required String fullName,
    required String role,
    required String status,
    String phoneNumber = '',
    String nim = '',
    String studyProgram = '',
    int? semester,
    String nip = '',
    String nidn = '',
  }) async {
    final cleanName = fullName.trim();

    _validateProfile(fullName: cleanName, role: role, status: status);
    _validateIdentity(
      phoneNumber: phoneNumber,
      nim: nim,
      studyProgram: studyProgram,
      semester: semester,
      nip: nip,
      nidn: nidn,
    );

    final userReference = _firestore.collection('users').doc(userId);

    final userDocument = await userReference.get();

    if (!userDocument.exists) {
      throw const UserManagementException('Pengguna tidak ditemukan.');
    }

    final data = userDocument.data()!;

    /// Superadmin bootstrap tidak boleh diturunkan role-nya
    /// atau dinonaktifkan melalui halaman umum.
    if (data['role'] == 'superadmin') {
      throw const UserManagementException(
        'Akun Superadmin utama tidak dapat diubah melalui halaman ini.',
      );
    }

    Object? normalized(Object? value) =>
        value is String ? (value.trim().isEmpty ? null : value.trim()) : value;
    final desired = <String, Object?>{
      'fullName': cleanName,
      'role': role,
      'status': status,
      'phoneNumber': phoneNumber.trim().isEmpty ? null : phoneNumber.trim(),
      'nim': role == 'student' && nim.trim().isNotEmpty ? nim.trim() : null,
      'studyProgram': role == 'student' && studyProgram.trim().isNotEmpty
          ? studyProgram.trim()
          : null,
      'semester': role == 'student' ? semester : null,
      'nip': role == 'lab_admin' && nip.trim().isNotEmpty ? nip.trim() : null,
      'nidn': role == 'lab_admin' && nidn.trim().isNotEmpty
          ? nidn.trim()
          : null,
    };
    final update = <String, Object?>{};
    for (final entry in desired.entries) {
      if (entry.key == 'semester'
          ? data[entry.key] != entry.value
          : normalized(data[entry.key]) != normalized(entry.value)) {
        update[entry.key] = entry.value;
      }
    }
    if (update.isEmpty) return false;

    /// Jika Lab Admin hendak diubah menjadi Student,
    /// jangan biarkan masih mempunyai membership aktif.
    if (data['role'] == 'lab_admin' && role != 'lab_admin') {
      final membership = await _firestore
          .collection('lab_memberships')
          .where('userId', isEqualTo: userId)
          .where('active', isEqualTo: true)
          .limit(1)
          .get();

      if (membership.docs.isNotEmpty) {
        throw const UserManagementException(
          'Role Lab Admin tidak dapat diubah karena masih memiliki '
          'membership laboratorium aktif. Nonaktifkan assignment terlebih dahulu.',
        );
      }
    }

    update['updatedAt'] = FieldValue.serverTimestamp();
    await userReference.update(update);
    return true;
  }

  void _validateIdentity({
    required String phoneNumber,
    required String nim,
    required String studyProgram,
    required int? semester,
    required String nip,
    required String nidn,
  }) {
    if (phoneNumber.trim().length > 20) {
      throw const UserManagementException('Nomor HP maksimal 20 karakter.');
    }
    if (nim.trim().length > 30) {
      throw const UserManagementException('NIM maksimal 30 karakter.');
    }
    if (studyProgram.trim().length > 100) {
      throw const UserManagementException(
        'Program studi maksimal 100 karakter.',
      );
    }
    if (semester != null && (semester < 1 || semester > 14)) {
      throw const UserManagementException(
        'Semester harus berada pada rentang 1–14.',
      );
    }
    if (nip.trim().length > 30 || nidn.trim().length > 30) {
      throw const UserManagementException('NIP dan NIDN maksimal 30 karakter.');
    }
  }

  /// Soft-delete pengguna.
  ///
  /// Karena client Firebase tidak boleh menghapus akun Auth user lain,
  /// akun dinonaktifkan melalui status Firestore.
  Future<bool> suspendUser(String userId) async {
    final currentUser = _firebaseAuth.currentUser;

    if (currentUser == null) {
      throw const UserManagementException('Sesi Superadmin tidak ditemukan.');
    }

    if (currentUser.uid == userId) {
      throw const UserManagementException(
        'Anda tidak dapat menonaktifkan akun sendiri.',
      );
    }

    final reference = _firestore.collection('users').doc(userId);

    final document = await reference.get();

    if (!document.exists) {
      throw const UserManagementException('Pengguna tidak ditemukan.');
    }

    final data = document.data()!;

    if (data['role'] == 'superadmin') {
      throw const UserManagementException(
        'Akun Superadmin tidak dapat dinonaktifkan melalui halaman ini.',
      );
    }

    if (data['status'] == 'suspended') {
      return false;
    }

    await reference.update({
      'status': 'suspended',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  /// Mengaktifkan kembali akun suspended.
  Future<bool> activateUser(String userId) async {
    final reference = _firestore.collection('users').doc(userId);

    final document = await reference.get();

    if (!document.exists) {
      throw const UserManagementException('Pengguna tidak ditemukan.');
    }

    if (document.data()?['status'] == 'active') {
      return false;
    }

    await reference.update({
      'status': 'active',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  /// Meminta backend tepercaya mengirim tautan verifikasi perubahan email.
  Future<void> requestEmailChange({
    required String userId,
    required String newEmail,
  }) async {
    try {
      await _credentialService.requestEmailChange(
        targetUid: userId,
        newEmail: newEmail,
      );
    } on AdminCredentialException catch (error) {
      throw UserManagementException(error.message);
    }
  }

  /// Meminta backend tepercaya mengirim tautan reset ke email akun target.
  Future<void> sendPasswordReset(String userId) async {
    try {
      await _credentialService.sendPasswordReset(targetUid: userId);
    } on AdminCredentialException catch (error) {
      throw UserManagementException(error.message);
    }
  }

  void _validateProfile({
    required String fullName,
    required String role,
    required String status,
  }) {
    if (fullName.isEmpty) {
      throw const UserManagementException('Nama pengguna wajib diisi.');
    }

    if (!_allowedRoles.contains(role)) {
      throw const UserManagementException('Role pengguna tidak valid.');
    }

    if (!_allowedStatuses.contains(status)) {
      throw const UserManagementException('Status pengguna tidak valid.');
    }
  }

  static const Set<String> _allowedRoles = {'student', 'lab_admin'};

  static const Set<String> _allowedStatuses = {'active', 'suspended'};

  String _firebaseAuthMessage(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'Email tersebut sudah digunakan oleh akun lain.';

      case 'invalid-email':
        return 'Format email tidak valid.';

      case 'weak-password':
        return 'Password terlalu lemah.';

      case 'network-request-failed':
        return 'Tidak dapat terhubung ke Firebase. Periksa koneksi internet.';

      case 'too-many-requests':
        return 'Terlalu banyak percobaan. Silakan coba kembali nanti.';

      default:
        return 'Gagal membuat akun pengguna.';
    }
  }
}

class UserManagementException implements Exception {
  const UserManagementException(this.message);

  final String message;

  @override
  String toString() => message;
}
