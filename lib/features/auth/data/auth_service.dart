import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../core/session/app_session_manager.dart';
import '../../../core/validators/auth_validator.dart';
import '../domain/user_profile.dart';

class AuthService {
  AuthService({
    FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
    AppSessionManager? sessionManager,
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _sessionManager = sessionManager ?? AppSessionManager.instance;

  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;
  final AppSessionManager _sessionManager;
  static final Map<String, UserProfile> _profileCache = <String, UserProfile>{};
  static int _cacheGeneration = 0;

  /// Menghapus seluruh cache profil di memori dan membatalkan generasi request lama.
  static void clearProfileCache([String? uid]) {
    _cacheGeneration++;
    if (uid != null) {
      _profileCache.remove(uid);
    } else {
      _profileCache.clear();
    }
  }

  /// Membaca cache profil untuk pengujian keamanan dan isolasi UID.
  @visibleForTesting
  static UserProfile? debugCachedProfile(String uid) => _profileCache[uid];

  /// User Firebase yang sedang login.
  User? get currentUser => _firebaseAuth.currentUser;
  String? get currentUid => _firebaseAuth.currentUser?.uid;

  /// Login menggunakan Firebase Authentication.
  ///
  /// Setelah email dan password berhasil diverifikasi,
  /// profil pengguna dibaca dari Firestore berdasarkan UID.
  Future<UserProfile> signIn({
    required String email,
    required String password,
  }) async {
    try {
      // Login baru tidak boleh mewarisi timestamp atau cache dari akun sebelumnya.
      clearProfileCache();
      await _sessionManager.clear();
      await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final expectedUid = _firebaseAuth.currentUser?.uid;
      if (expectedUid == null) {
        await signOut();
        throw const AuthServiceException(
          'Sesi login tidak ditemukan. Silakan masuk kembali.',
          code: AuthServiceException.sessionNotFound,
        );
      }
      final requestGeneration = _cacheGeneration;
      final profile = await _loadCurrentUserProfile(expectedUid: expectedUid);
      if (_cacheGeneration != requestGeneration || currentUid != expectedUid) {
        throw const AuthServiceException(
          'Sesi login telah berubah. Silakan masuk kembali.',
          code: AuthServiceException.sessionNotFound,
        );
      }
      _profileCache
        ..clear()
        ..[profile.uid] = profile;
      try {
        await _sessionManager.start(profile.uid);
      } catch (_) {
        await signOut();
        throw const AuthServiceException(
          'Sesi lokal tidak dapat disimpan. Silakan coba login kembali.',
          code: AuthServiceException.sessionNotFound,
        );
      }
      return profile;
    } on FirebaseAuthException catch (error) {
      throw AuthServiceException(
        _firebaseMessage(error.code),
        code: _firebaseErrorCode(error.code),
      );
    }
  }

  /// Membaca profil user yang sedang login dari Firestore.
  ///
  /// Method ini menjadi pemeriksaan authoritative untuk session,
  /// keberadaan profil, dan status aktif akun.
  ///
  /// Halaman berdasarkan role tetap memanggil method ini agar
  /// akses tidak hanya bergantung pada routing UI.
  Future<UserProfile> getCurrentUserProfile({bool forceRefresh = false}) async {
    await requireValidSession();
    final uid = currentUid;
    if (uid == null) {
      await signOut();
      throw const AuthServiceException(
        'Sesi login tidak ditemukan. Silakan masuk kembali.',
        code: AuthServiceException.sessionNotFound,
      );
    }
    // Pastikan cache hanya menyimpan milik UID yang sedang login.
    if (_profileCache.keys.any((cachedUid) => cachedUid != uid)) {
      _cacheGeneration++;
      _profileCache.removeWhere((cachedUid, _) => cachedUid != uid);
    }
    if (!forceRefresh && _profileCache.containsKey(uid)) {
      final cached = _profileCache[uid]!;
      if (cached.uid == uid &&
          cached.isActive &&
          isSupportedRole(cached.role)) {
        return cached;
      }
      _profileCache.remove(uid);
    }
    final requestGeneration = _cacheGeneration;
    final profile = await _loadCurrentUserProfile(expectedUid: uid);
    if (_cacheGeneration == requestGeneration &&
        currentUid == uid &&
        profile.uid == uid &&
        profile.isActive &&
        isSupportedRole(profile.role)) {
      final validSession = await _sessionManager.validFor(uid);
      if (validSession != null &&
          _cacheGeneration == requestGeneration &&
          currentUid == uid) {
        _profileCache
          ..clear()
          ..[profile.uid] = profile;
        return profile;
      }
    }
    throw const AuthServiceException(
      'Sesi login telah berubah atau berakhir. Silakan masuk kembali.',
      code: AuthServiceException.sessionNotFound,
    );
  }

  Future<AppSession> requireValidSession() async {
    final uid = _firebaseAuth.currentUser?.uid;
    if (uid != null) {
      final session = await _sessionManager.validFor(uid);
      if (session != null) return session;
    }
    await signOut();
    throw const AuthServiceException(
      'Sesi Anda telah berakhir. Silakan masuk kembali.',
      code: AuthServiceException.sessionNotFound,
    );
  }

  Future<UserProfile> _loadCurrentUserProfile({
    required String expectedUid,
  }) async {
    final user = _firebaseAuth.currentUser;

    if (user == null || user.uid != expectedUid) {
      clearProfileCache();
      throw const AuthServiceException(
        'Sesi login tidak ditemukan. Silakan masuk kembali.',
        code: AuthServiceException.sessionNotFound,
      );
    }

    final profileDocument = await _firestore
        .collection('users')
        .doc(expectedUid)
        .get();

    // Jika sesi atau UID aktif berubah saat menunggu jaringan, jangan proses hasil lama.
    final activeUidAfterRead = _firebaseAuth.currentUser?.uid;
    if (activeUidAfterRead == null || activeUidAfterRead != expectedUid) {
      throw const AuthServiceException(
        'Sesi login telah berubah. Silakan masuk kembali.',
        code: AuthServiceException.sessionNotFound,
      );
    }

    if (!profileDocument.exists) {
      await signOut();

      throw const AuthServiceException(
        'Profil akun tidak ditemukan di database.',
        code: AuthServiceException.profileNotFound,
      );
    }

    final profile = UserProfile.fromDocument(profileDocument);

    if (!profile.isActive) {
      /// Session Firebase langsung diakhiri agar akun suspended
      /// tidak tetap memiliki session aktif pada client.
      await signOut();

      throw const AuthServiceException(
        'Akun Anda sedang dinonaktifkan. Hubungi Admin Lab.',
        code: AuthServiceException.accountSuspended,
      );
    }

    if (!isSupportedRole(profile.role)) {
      await signOut();

      throw const AuthServiceException(
        'Role akun tidak dikenali.',
        code: AuthServiceException.invalidRole,
      );
    }

    return profile;
  }

  /// Keluar dari Firebase Authentication.
  Future<void> signOut() async {
    try {
      clearProfileCache();
      await _firebaseAuth.signOut();
    } finally {
      clearProfileCache();
      await _sessionManager.clear();
    }
  }

  /// Mengganti password akun Firebase yang sedang login.
  ///
  /// Identitas selalu diambil dari `currentUser`; email atau UID dari input
  /// pengguna tidak pernah digunakan untuk memilih akun.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw const AuthServiceException(
        'Sesi login tidak ditemukan. Silakan masuk kembali.',
        code: AuthServiceException.sessionNotFound,
      );
    }

    final email = user.email?.trim();
    if (email == null || email.isEmpty) {
      throw const AuthServiceException(
        'Email akun tidak tersedia untuk verifikasi.',
        code: AuthServiceException.invalidCredential,
      );
    }

    if (currentPassword.isEmpty) {
      throw const AuthServiceException(
        'Password saat ini wajib diisi.',
        code: AuthServiceException.validation,
      );
    }

    final newPasswordError = AuthValidator.validatePassword(newPassword);
    if (newPasswordError != null) {
      throw AuthServiceException(
        newPasswordError,
        code: AuthServiceException.validation,
      );
    }

    if (currentPassword == newPassword) {
      throw const AuthServiceException(
        'Password baru harus berbeda dari password saat ini.',
        code: AuthServiceException.validation,
      );
    }

    try {
      final credential = EmailAuthProvider.credential(
        email: email,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (error) {
      throw AuthServiceException(
        _passwordMessage(error.code),
        code: error.code,
      );
    }
  }

  /// Mengirim tautan reset password tanpa mengungkapkan keberadaan akun.
  Future<void> sendPasswordResetEmail({required String email}) async {
    final normalizedEmail = email.trim();
    final validationError = AuthValidator.validateEmail(normalizedEmail);
    if (validationError != null) {
      throw AuthServiceException(
        validationError,
        code: AuthServiceException.validation,
      );
    }

    try {
      await _firebaseAuth.sendPasswordResetEmail(email: normalizedEmail);
    } on FirebaseAuthException catch (error) {
      throw AuthServiceException(
        _passwordResetMessage(error.code),
        code: error.code,
      );
    }
  }

  static bool isSupportedRole(String role) =>
      role == 'student' || role == 'lab_admin' || role == 'superadmin';

  /// Mengubah kode error Firebase Authentication menjadi kode
  /// domain yang dapat dikenali presentation layer.
  ///
  /// Firebase `user-disabled` dipetakan ke account-suspended
  /// supaya menggunakan state UI yang sama dengan status
  /// suspended pada profil Firestore.
  String _firebaseErrorCode(String code) {
    switch (code) {
      case 'user-disabled':
        return AuthServiceException.accountSuspended;

      default:
        return code;
    }
  }

  /// Pesan aman yang ditampilkan ke pengguna.
  String _firebaseMessage(String code) {
    switch (code) {
      case 'invalid-email':
        return 'Format email tidak valid.';

      case 'user-disabled':
        return 'Akun Anda sedang dinonaktifkan. Hubungi Admin Lab.';

      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email atau password tidak sesuai.';

      case 'too-many-requests':
        return 'Terlalu banyak percobaan login. Coba lagi nanti.';

      case 'network-request-failed':
        return 'Tidak dapat terhubung ke internet.';

      default:
        return 'Login gagal. Silakan coba kembali.';
    }
  }

  String _passwordMessage(String code) {
    switch (code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'Password saat ini tidak sesuai.';
      case 'requires-recent-login':
        return 'Demi keamanan, silakan login kembali lalu ulangi perubahan password.';
      case 'weak-password':
        return 'Password baru terlalu lemah.';
      case 'user-disabled':
        return 'Akun Anda sedang dinonaktifkan.';
      case 'user-not-found':
        return 'Akun tidak dapat ditemukan. Silakan login kembali.';
      case 'network-request-failed':
        return 'Tidak dapat terhubung ke internet.';
      case 'too-many-requests':
        return 'Terlalu banyak percobaan. Coba lagi nanti.';
      default:
        return 'Password tidak dapat diubah. Silakan coba kembali.';
    }
  }

  String _passwordResetMessage(String code) {
    switch (code) {
      case 'network-request-failed':
        return 'Tidak dapat terhubung ke internet.';
      case 'too-many-requests':
        return 'Terlalu banyak permintaan. Coba lagi nanti.';
      default:
        return 'Tautan reset password belum dapat dikirim. Silakan coba lagi.';
    }
  }
}

/// Exception domain untuk proses authentication LabFlow.
///
/// `code` digunakan oleh presentation layer untuk menentukan
/// state UI tanpa bergantung pada pencocokan isi message.
class AuthServiceException implements Exception {
  const AuthServiceException(this.message, {this.code = unknown});

  /// Kode domain yang digunakan lintas authentication flow.
  static const String sessionNotFound = 'session-not-found';
  static const String profileNotFound = 'profile-not-found';
  static const String accountSuspended = 'account-suspended';
  static const String invalidRole = 'invalid-role';
  static const String invalidCredential = 'invalid-credential';
  static const String validation = 'validation';
  static const String unknown = 'unknown';

  final String message;
  final String code;

  /// Memudahkan pemeriksaan kondisi suspended tanpa
  /// membandingkan string message pada presentation layer.
  bool get isAccountSuspended => code == accountSuspended;

  @override
  String toString() => message;
}
