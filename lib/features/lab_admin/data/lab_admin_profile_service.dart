import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../auth/data/auth_service.dart';
import '../domain/lab_admin_profile.dart';

class LabAdminProfileService {
  LabAdminProfileService({
    FirebaseFirestore? firestore,
    FirebaseAuth? firebaseAuth,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _firebaseAuth;

  Future<LabAdminProfile> loadProfile() async {
    final user = _firebaseAuth.currentUser;

    if (user == null) {
      throw const LabAdminProfileException('Sesi Lab Admin tidak ditemukan.');
    }

    try {
      final userSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userSnapshot.exists) {
        throw const LabAdminProfileException(
          'Profil Lab Admin tidak ditemukan.',
        );
      }

      final userData = userSnapshot.data();

      if (userData == null) {
        throw const LabAdminProfileException(
          'Data profil Lab Admin tidak valid.',
        );
      }

      final role = (userData['role'] as String? ?? '').trim();
      final status = (userData['status'] as String? ?? 'active').trim();

      if (status != 'active') {
        await signOut();
        throw const LabAdminProfileException(
          'Akun Anda sedang dinonaktifkan. Hubungi Admin Lab.',
        );
      }

      if (role != 'lab_admin') {
        AuthService.clearProfileCache(user.uid);
        throw const LabAdminProfileException('Akun ini bukan akun Lab Admin.');
      }

      final membershipsSnapshot = await _firestore
          .collection('lab_memberships')
          .where('userId', isEqualTo: user.uid)
          .get();

      final activeLabIds = membershipsSnapshot.docs
          .where((document) {
            final data = document.data();

            return data['active'] == true &&
                (data['role'] as String? ?? '').trim() == 'lab_admin';
          })
          .map((document) => (document.data()['labId'] as String? ?? '').trim())
          .where((labId) => labId.isNotEmpty)
          .toSet()
          .toList(growable: false);

      final laboratorySnapshots = await Future.wait(
        activeLabIds.map(
          (labId) => _firestore.collection('laboratories').doc(labId).get(),
        ),
      );

      final laboratories =
          laboratorySnapshots
              .where((snapshot) => snapshot.exists)
              .map((snapshot) {
                final data = snapshot.data() ?? const <String, dynamic>{};

                return LabAdminProfileLaboratory(
                  id: snapshot.id,
                  code: (data['code'] as String? ?? '-').trim(),
                  name: (data['name'] as String? ?? 'Laboratorium').trim(),
                  location: (data['location'] as String? ?? '-').trim(),
                );
              })
              .toList(growable: false)
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );

      final fullName =
          (userData['fullName'] as String? ??
                  userData['name'] as String? ??
                  user.displayName ??
                  '')
              .trim();

      final email = (userData['email'] as String? ?? user.email ?? '').trim();

      return LabAdminProfile(
        uid: user.uid,
        fullName: fullName,
        email: email,
        role: (userData['role'] as String? ?? 'lab_admin').trim(),
        status: (userData['status'] as String? ?? 'active').trim(),
        laboratories: laboratories,
        profilePhotoUrl: userData['profilePhotoUrl'] as String?,
        phoneNumber: userData['phoneNumber'] as String?,
        nip: userData['nip'] as String?,
        nidn: userData['nidn'] as String?,
      );
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw const LabAdminProfileException(
          'Firestore menolak pembacaan profil. '
          'Periksa status akun dan membership laboratorium.',
        );
      }

      throw LabAdminProfileException(
        'Profil Lab Admin gagal dimuat (${error.code}).',
      );
    }
  }

  Future<void> signOut() async {
    try {
      await AuthService(
        firebaseAuth: _firebaseAuth,
        firestore: _firestore,
      ).signOut();
    } on FirebaseAuthException catch (error) {
      throw LabAdminProfileException('Logout gagal (${error.code}).');
    }
  }
}

class LabAdminProfileException implements Exception {
  const LabAdminProfileException(this.message);

  final String message;

  @override
  String toString() => message;
}
