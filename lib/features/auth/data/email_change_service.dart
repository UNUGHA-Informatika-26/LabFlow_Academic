import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/validators/auth_validator.dart';
import '../domain/email_change_request.dart';

class EmailChangeService {
  EmailChangeService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('email_change_requests');

  /// Mendengarkan permohonan email aktif milik pengguna saat ini.
  Stream<EmailChangeRequest?> watchMyActiveRequest() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value(null);
    }
    return _collection
        .where('uid', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) {
          final docs = snapshot.docs.map(EmailChangeRequest.fromDocument).toList();
          // Cari request yang masih aktif (pending atau approved)
          final active = docs.where((r) => r.isPending || r.isApproved).toList();
          if (active.isEmpty) return null;
          active.sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
          return active.first;
        });
  }

  /// Membuat permohonan perubahan email baru.
  Future<String> submitRequest({
    required String newEmail,
    required String reason,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const EmailChangeException('Sesi pengguna tidak ditemukan.');
    }

    final trimmedEmail = newEmail.trim().toLowerCase();
    final currentEmail = (user.email ?? '').trim().toLowerCase();

    final validationError = AuthValidator.validateEmail(trimmedEmail);
    if (validationError != null) {
      throw EmailChangeException(validationError);
    }

    if (trimmedEmail == currentEmail) {
      throw const EmailChangeException(
        'Email baru harus berbeda dari email akun saat ini.',
      );
    }

    final trimmedReason = reason.trim();
    if (trimmedReason.length < 5) {
      throw const EmailChangeException(
        'Alasan perubahan email minimal 5 karakter.',
      );
    }

    // Pastikan tidak ada request pending yang duplikat
    final pendingSnapshot = await _collection
        .where('uid', isEqualTo: user.uid)
        .where('status', isEqualTo: 'pending')
        .get();

    if (pendingSnapshot.docs.isNotEmpty) {
      throw const EmailChangeException(
        'Anda masih memiliki permohonan perubahan email yang menunggu persetujuan.',
      );
    }

    final docRef = _collection.doc();
    final request = EmailChangeRequest(
      id: docRef.id,
      uid: user.uid,
      currentEmail: currentEmail,
      requestedEmail: trimmedEmail,
      reason: trimmedReason,
      status: 'pending',
      requestedAt: DateTime.now(),
    );

    await docRef.set(request.toMap());
    return docRef.id;
  }

  /// Memverifikasi dan meminta Auth mengirim tautan verifikasi ke email baru.
  Future<void> sendVerificationLink(EmailChangeRequest request) async {
    final user = _auth.currentUser;
    if (user == null || user.uid != request.uid) {
      throw const EmailChangeException('Sesi pemilik permohonan tidak valid.');
    }

    if (!request.isApproved) {
      throw const EmailChangeException(
        'Permohonan harus disetujui Superadmin sebelum verifikasi email dapat dikirim.',
      );
    }

    try {
      await user.verifyBeforeUpdateEmail(request.requestedEmail);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        throw const EmailChangeException(
          'Demi keamanan, silakan masuk ulang (re-login) sebelum melanjutkan verifikasi.',
          code: 'requires-recent-login',
        );
      }
      throw EmailChangeException(
        'Gagal mengirim verifikasi: ${e.message ?? e.code}',
        code: e.code,
      );
    } catch (e) {
      throw EmailChangeException('Gagal mengirim verifikasi email: $e');
    }
  }

  /// Memeriksa apakah email baru telah diverifikasi di Firebase Auth,
  /// memaksa refresh ID token agar klaim terbaru terbaca oleh Firestore Rules,
  /// kemudian menyinkronkan email profil ke Firestore dan menandai request selesai.
  Future<bool> checkAndSyncVerifiedEmail(EmailChangeRequest request) async {
    final user = _auth.currentUser;
    if (user == null || user.uid != request.uid) {
      throw const EmailChangeException('Sesi pengguna tidak valid.');
    }

    final expectedUid = user.uid;

    // Reload state dari server Firebase Authentication
    await user.reload();
    final reloadedUser = _auth.currentUser;
    if (reloadedUser == null) {
      throw const EmailChangeException('Gagal memuat ulang sesi pengguna.');
    }
    if (reloadedUser.uid != expectedUid) {
      throw const EmailChangeException(
        'Identitas pengguna berubah selama proses verifikasi.',
      );
    }

    final currentAuthEmail = (reloadedUser.email ?? '').trim().toLowerCase();
    final requestedEmail = request.requestedEmail.trim().toLowerCase();

    // Hentikan sebelum refresh token / sync jika Auth email belum cocok atau belum terverifikasi
    if (currentAuthEmail != requestedEmail || !reloadedUser.emailVerified) {
      return false;
    }

    // Paksa pembaruan ID Token sebelum mutasi Firestore agar request.auth.token
    // mencerminkan klaim email dan email_verified terbaru ke Security Rules.
    try {
      final token = await reloadedUser.getIdToken(true);
      if (token == null || token.isEmpty) {
        throw const EmailChangeException(
          'Token verifikasi terbaru tidak tersedia.',
        );
      }
    } on EmailChangeException {
      rethrow;
    } on FirebaseAuthException catch (e) {
      throw EmailChangeException(
        'Gagal memperbarui sesi verifikasi: ${e.message ?? e.code}',
        code: e.code,
      );
    } catch (e) {
      throw EmailChangeException('Gagal memperbarui token sesi: $e');
    }

    // Sinkronkan ke dokumen Firestore users/{uid}
    await _firestore.collection('users').doc(reloadedUser.uid).update({
      'email': requestedEmail,
      'emailVerified': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Tandai request menjadi completed
    await _collection.doc(request.id).update({
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
    });

    return true;
  }

  // =========================================================
  // SUPERADMIN APPROVAL FLOW
  // =========================================================

  /// Mengamati seluruh permohonan email pending untuk Superadmin.
  Stream<List<EmailChangeRequest>> watchPendingRequests() {
    return _collection
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) {
          final items = snap.docs.map(EmailChangeRequest.fromDocument).toList();
          items.sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
          return items;
        });
  }

  /// Mengamati seluruh riwayat permohonan email untuk Superadmin.
  Stream<List<EmailChangeRequest>> watchAllRequests() {
    return _collection.snapshots().map((snap) {
      final items = snap.docs.map(EmailChangeRequest.fromDocument).toList();
      items.sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
      return items;
    });
  }

  /// Menyetujui permohonan perubahan email (Superadmin).
  Future<void> approveRequest(String requestId) async {
    final adminUser = _auth.currentUser;
    if (adminUser == null) {
      throw const EmailChangeException('Sesi Superadmin tidak ditemukan.');
    }

    final ref = _collection.doc(requestId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) {
        throw const EmailChangeException('Permohonan tidak ditemukan.');
      }
      final currentStatus = snapshot.data()?['status'] as String?;
      if (currentStatus != 'pending') {
        throw const EmailChangeException(
          'Permohonan ini sudah diproses sebelumnya.',
        );
      }
      transaction.update(ref, {
        'status': 'approved',
        'reviewedBy': adminUser.uid,
        'reviewedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Menolak permohonan perubahan email (Superadmin).
  Future<void> rejectRequest({
    required String requestId,
    required String rejectionReason,
  }) async {
    final adminUser = _auth.currentUser;
    if (adminUser == null) {
      throw const EmailChangeException('Sesi Superadmin tidak ditemukan.');
    }

    final reason = rejectionReason.trim();
    if (reason.isEmpty) {
      throw const EmailChangeException('Alasan penolakan wajib diisi.');
    }

    final ref = _collection.doc(requestId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) {
        throw const EmailChangeException('Permohonan tidak ditemukan.');
      }
      final currentStatus = snapshot.data()?['status'] as String?;
      if (currentStatus != 'pending') {
        throw const EmailChangeException(
          'Permohonan ini sudah diproses sebelumnya.',
        );
      }
      transaction.update(ref, {
        'status': 'rejected',
        'rejectionReason': reason,
        'reviewedBy': adminUser.uid,
        'reviewedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}

class EmailChangeException implements Exception {
  const EmailChangeException(this.message, {this.code});
  final String message;
  final String? code;

  @override
  String toString() => message;
}
