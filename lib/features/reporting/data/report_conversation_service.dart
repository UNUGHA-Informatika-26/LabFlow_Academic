import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';

import '../../asset/data/asset_image_service.dart';
import '../../../core/connectivity/connectivity_service.dart';
import '../domain/report_message.dart';

class ReportConversationService {
  ReportConversationService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    AssetImageService? images,
    ConnectivityService? connectivity,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _images = images ?? AssetImageService(),
        _connectivity = connectivity ?? PluginConnectivityService();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final AssetImageService _images;
  final ConnectivityService _connectivity;

  static String? validateMessage(String value, {bool hasImage = false}) {
    final text = value.trim();
    if (text.isEmpty && !hasImage) return 'Pesan tidak boleh kosong.';
    if (text.length > 1000) return 'Pesan maksimal 1000 karakter.';
    return null;
  }

  Stream<List<ReportMessage>> watchMessages(String reportId) => _firestore
      .collection('reports')
      .doc(reportId)
      .collection('messages')
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map(ReportMessage.fromDocument)
            .toList(growable: false)
            .reversed
            .toList(growable: false),
      );

  Future<void> send(String reportId, String rawText, {XFile? image}) async {
    final validation = validateMessage(rawText, hasImage: image != null);
    if (validation != null) throw ReportConversationException(validation);
    final user = _auth.currentUser;
    if (user == null) {
      throw const ReportConversationException('Sesi pengguna tidak ditemukan.');
    }
    DocumentSnapshot<Map<String, dynamic>> profile;
    try {
      profile = await _firestore.collection('users').doc(user.uid).get();
    } on FirebaseException catch (error) {
      throw ReportConversationException(_firestoreMessage(error));
    }
    final data = profile.data();
    final role = (data?['role'] as String? ?? '').trim();
    if (data?['status'] != 'active' ||
        !{'student', 'lab_admin'}.contains(role)) {
      throw const ReportConversationException(
        'Akun tidak dapat mengirim pesan.',
      );
    }
    CloudinaryImageUpload? upload;
    if (image != null) {
      if (!await _connectivity.hasNetworkInterface()) {
        throw const ReportConversationException(
          'Upload gambar membutuhkan koneksi internet.',
        );
      }
      try {
        upload = await _images.uploadImage(
          image: image,
          folder: 'labflow/reports/$reportId/chat',
          maximumBytes: 5 * 1024 * 1024,
        );
      } on AssetImageException catch (error) {
        throw ReportConversationException(error.message);
      }
    }
    final messageType = upload == null
        ? 'text'
        : rawText.trim().isEmpty
        ? 'image'
        : 'mixed';
    try {
      await _firestore
          .collection('reports')
          .doc(reportId)
          .collection('messages')
          .add({
            'senderId': user.uid,
            'senderRole': role,
            'senderName': (data?['fullName'] as String? ?? '').trim(),
            'text': rawText.trim(),
            'type': messageType,
            if (upload != null) 'imageUrl': upload.secureUrl,
            if (upload?.publicId != null) 'imagePublicId': upload!.publicId,
            'createdAt': FieldValue.serverTimestamp(),
            'deletedAt': null,
          });
    } on FirebaseException catch (error) {
      throw ReportConversationException(_firestoreMessage(error));
    }
  }

  Future<void> softDelete(String reportId, String messageId) async {
    await _firestore
        .collection('reports')
        .doc(reportId)
        .collection('messages')
        .doc(messageId)
        .update({'deletedAt': FieldValue.serverTimestamp()});
  }

  String _firestoreMessage(FirebaseException error) => switch (error.code) {
    'permission-denied' =>
      'Firestore menolak pesan. Periksa akses percakapan dan Rules aktif.',
    'unavailable' || 'deadline-exceeded' =>
      'Tidak dapat terhubung ke Firestore. Periksa koneksi.',
    _ => 'Pesan gagal disimpan ke Firestore. Coba lagi.',
  };
}

class ReportConversationException implements Exception {
  const ReportConversationException(this.message);
  final String message;
  @override
  String toString() => message;
}
