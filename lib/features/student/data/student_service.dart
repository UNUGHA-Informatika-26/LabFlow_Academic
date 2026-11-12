import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../auth/data/auth_service.dart';
import '../../../core/offline/borrow_draft_store.dart';
import '../domain/student_models.dart';

class StudentService {
  StudentService({
    FirebaseFirestore? firestore,
    FirebaseAuth? firebaseAuth,
    BorrowDraftStore? draftStore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _draftStore = draftStore ?? SharedPreferencesBorrowDraftStore();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _firebaseAuth;
  final BorrowDraftStore _draftStore;

  String get _uid {
    final user = _firebaseAuth.currentUser;

    if (user == null) {
      throw const StudentServiceException('Sesi mahasiswa tidak ditemukan.');
    }

    return user.uid;
  }

  Future<BorrowRequestDraft?> loadBorrowDraft(String assetId) =>
      _draftStore.read(_uid, assetId);

  Future<void> saveBorrowDraft({
    required String assetId,
    required int quantity,
    required DateTime borrowDate,
    required DateTime returnDate,
    required String purpose,
    required String note,
  }) => _draftStore.write(
    _uid,
    BorrowRequestDraft(
      assetId: assetId,
      quantity: quantity,
      borrowDate: borrowDate,
      returnDate: returnDate,
      purpose: purpose.trim(),
      note: note.trim(),
      updatedAt: DateTime.now().toUtc(),
    ),
  );

  Future<void> removeBorrowDraft(String assetId) =>
      _draftStore.remove(_uid, assetId);

  Future<StudentProfile> loadProfile() async {
    final uid = _uid;
    final authUser = _firebaseAuth.currentUser;
    final snapshot = await _firestore.collection('users').doc(uid).get();

    if (!snapshot.exists) {
      throw const StudentServiceException('Profil mahasiswa tidak ditemukan.');
    }

    final data = snapshot.data() ?? const <String, dynamic>{};
    final role = (data['role'] as String? ?? '').trim();
    final status = (data['status'] as String? ?? 'active').trim();

    if (status != 'active') {
      await signOut();
      throw const StudentServiceException(
        'Akun Anda sedang dinonaktifkan. Hubungi Admin Lab.',
      );
    }

    if (role != 'student') {
      AuthService.clearProfileCache(uid);
      throw const StudentServiceException('Akun ini bukan akun Student.');
    }

    return StudentProfile(
      uid: uid,
      fullName:
          (data['fullName'] as String? ??
                  data['name'] as String? ??
                  authUser?.displayName ??
                  '')
              .trim(),
      email: (data['email'] as String? ?? authUser?.email ?? '').trim(),
      status: (data['status'] as String? ?? 'active').trim(),
      profilePhotoUrl: data['profilePhotoUrl'] as String?,
      phoneNumber: data['phoneNumber'] as String?,
      nim: data['nim'] as String?,
      studyProgram: data['studyProgram'] as String?,
      semester: data['semester'] as int?,
    );
  }

  Future<List<StudentLaboratory>> loadActiveLaboratories() async {
    final snapshot = await _firestore
        .collection('laboratories')
        .where('status', isEqualTo: 'active')
        .get();

    final laboratories =
        snapshot.docs.map(StudentLaboratory.fromDocument).toList()..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );

    return laboratories;
  }

  Future<List<StudentAsset>> loadAssets() async {
    final snapshot = await _firestore.collection('assets').get();

    final assets = snapshot.docs.map(StudentAsset.fromDocument).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return assets;
  }

  Future<StudentAsset> loadAsset(String assetId) async {
    final snapshot = await _firestore.collection('assets').doc(assetId).get();

    if (!snapshot.exists) {
      throw const StudentServiceException('Aset tidak ditemukan.');
    }

    return StudentAsset.fromDocument(snapshot);
  }

  Future<StudentBorrowSubmissionResult> createBorrowRequest({
    required StudentAsset asset,
    required int quantity,
    required DateTime borrowDate,
    required DateTime expectedReturnDate,
    required String purpose,
    String? studentNote,
  }) async {
    final cleanPurpose = purpose.trim();
    final cleanNote = studentNote?.trim();
    final uid = _uid;

    if (!asset.isAvailable) {
      throw const StudentServiceException(
        'Aset sedang tidak tersedia untuk dipinjam.',
      );
    }

    if (quantity < 1) {
      throw const StudentServiceException('Jumlah peminjaman minimal 1 unit.');
    }

    if (quantity > asset.stock) {
      throw StudentServiceException(
        'Stok ${asset.name} hanya tersedia ${asset.stock} unit.',
      );
    }

    if (cleanPurpose.length < 3) {
      throw const StudentServiceException(
        'Tujuan peminjaman minimal 3 karakter.',
      );
    }

    if (cleanPurpose.length > 300) {
      throw const StudentServiceException(
        'Tujuan peminjaman maksimal 300 karakter.',
      );
    }

    if (cleanNote != null && cleanNote.length > 1000) {
      throw const StudentServiceException('Catatan maksimal 1000 karakter.');
    }

    final borrowDay = DateTime(
      borrowDate.year,
      borrowDate.month,
      borrowDate.day,
      8,
    );
    final returnDay = DateTime(
      expectedReturnDate.year,
      expectedReturnDate.month,
      expectedReturnDate.day,
      17,
    );

    if (returnDay.isBefore(borrowDay)) {
      throw const StudentServiceException(
        'Tanggal kembali tidak boleh sebelum tanggal pinjam.',
      );
    }

    final latestAssetSnapshot = await _firestore
        .collection('assets')
        .doc(asset.id)
        .get(const GetOptions(source: Source.server));

    if (!latestAssetSnapshot.exists) {
      throw const StudentServiceException('Aset tidak ditemukan.');
    }

    final latestAsset = StudentAsset.fromDocument(latestAssetSnapshot);

    if (latestAsset.labId != asset.labId ||
        !latestAsset.isAvailable ||
        latestAsset.condition == 'damaged' ||
        latestAsset.stock < quantity) {
      throw const StudentServiceException(
        'Ketersediaan aset telah berubah. Muat ulang katalog lalu coba lagi.',
      );
    }

    final laboratorySnapshot = await _firestore
        .collection('laboratories')
        .doc(asset.labId)
        .get(const GetOptions(source: Source.server));
    final laboratoryData = laboratorySnapshot.data();

    if (!laboratorySnapshot.exists ||
        laboratoryData == null ||
        laboratoryData['status'] != 'active') {
      throw const StudentServiceException(
        'Laboratorium sedang tidak aktif untuk pengajuan peminjaman.',
      );
    }

    final requestReference = _firestore.collection('borrow_requests').doc();
    final profileSnapshot = await _firestore.collection('users').doc(uid).get();
    final profileName = (profileSnapshot.data()?['fullName'] as String? ?? '')
        .trim();
    if (!profileSnapshot.exists || profileName.isEmpty) {
      throw const StudentServiceException(
        'Nama pada profil belum tersedia. Lengkapi profil sebelum mengajukan peminjaman.',
      );
    }
    final now = DateTime.now();
    final shortId = requestReference.id
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .toUpperCase();
    final suffix = shortId.length >= 6 ? shortId.substring(0, 6) : shortId;
    final requestNumber = 'BRW-${now.year}-$suffix';
    final itemReference = requestReference.collection('items').doc();

    final requestData = {
      'requestNumber': requestNumber,
      'studentId': uid,
      'studentName': profileName,
      'labId': asset.labId,
      'purpose': cleanPurpose,
      'borrowDate': Timestamp.fromDate(borrowDay),
      'expectedReturnDate': Timestamp.fromDate(returnDay),
      'status': 'pending',
      'studentNote': cleanNote == null || cleanNote.isEmpty ? null : cleanNote,
      'approvedBy': null,
      'approvedAt': null,
      'rejectionReason': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final itemData = {
      'itemId': asset.id,
      'itemName': latestAsset.name,
      'quantity': quantity,
      'requestedAssetId': asset.id,
      if (latestAsset.code.trim().isNotEmpty && latestAsset.code.trim() != '-')
        'requestedAssetCode': latestAsset.code.trim(),
    };

    try {
      // Firestore transactions require a server connection. This prevents the
      // final borrowing request from becoming a blind offline queued write.
      await _firestore.runTransaction((transaction) async {
        transaction.set(requestReference, requestData);
        transaction.set(itemReference, itemData);
      });
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw const StudentServiceException(
          'Pengajuan ditolak oleh aturan keamanan. Muat ulang data lalu coba lagi.',
        );
      }

      if (error.code == 'unavailable' || error.code == 'deadline-exceeded') {
        throw const StudentServiceException(
          'Koneksi internet diperlukan untuk mengirim pengajuan. Simpan sebagai draft lalu kirim setelah online.',
        );
      }

      throw StudentServiceException(
        'Pengajuan peminjaman gagal (${error.code}).',
      );
    }

    return StudentBorrowSubmissionResult(
      requestId: requestReference.id,
      requestNumber: requestNumber,
    );
  }

  Future<void> cancelBorrowRequest(String requestId) async {
    final cleanId = requestId.trim();

    if (cleanId.isEmpty) {
      throw const StudentServiceException(
        'ID pengajuan peminjaman tidak valid.',
      );
    }

    final reference = _firestore.collection('borrow_requests').doc(cleanId);

    try {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(reference);

        if (!snapshot.exists) {
          throw const StudentServiceException(
            'Pengajuan peminjaman tidak ditemukan.',
          );
        }

        final data = snapshot.data();

        if (data == null || data['studentId'] != _uid) {
          throw const StudentServiceException(
            'Anda tidak memiliki akses ke pengajuan ini.',
          );
        }

        if (data['status'] != 'pending') {
          throw const StudentServiceException(
            'Hanya pengajuan yang masih menunggu yang dapat dibatalkan.',
          );
        }

        transaction.update(reference, {
          'status': 'cancelled',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw const StudentServiceException(
          'Pengajuan tidak dapat dibatalkan karena akses ditolak.',
        );
      }

      throw StudentServiceException(
        'Pembatalan pengajuan gagal (${error.code}).',
      );
    }
  }

  Future<List<StudentBorrowRequest>> loadBorrowRequests() async {
    final snapshot = await _firestore
        .collection('borrow_requests')
        .where('studentId', isEqualTo: _uid)
        .get();

    final requests =
        snapshot.docs.map(StudentBorrowRequest.fromDocument).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return requests;
  }

  Future<List<StudentReport>> loadReports() async {
    final snapshot = await _firestore
        .collection('reports')
        .where('reporterId', isEqualTo: _uid)
        .get();

    final reports = snapshot.docs.map(StudentReport.fromDocument).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return reports;
  }

  Future<StudentHomeData> loadHomeData() async {
    final results = await Future.wait<dynamic>([
      loadProfile(),
      loadActiveLaboratories(),
      loadAssets(),
      loadBorrowRequests(),
      loadReports(),
    ]);

    return StudentHomeData(
      profile: results[0] as StudentProfile,
      laboratories: results[1] as List<StudentLaboratory>,
      assets: results[2] as List<StudentAsset>,
      borrowRequests: results[3] as List<StudentBorrowRequest>,
      reports: results[4] as List<StudentReport>,
    );
  }

  Future<void> signOut() async {
    await AuthService(
      firebaseAuth: _firebaseAuth,
      firestore: _firestore,
    ).signOut();
  }
}

class StudentServiceException implements Exception {
  const StudentServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
