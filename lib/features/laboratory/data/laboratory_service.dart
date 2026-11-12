import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/offline/conflict_resolution.dart';
import '../domain/laboratory.dart';

class LaboratoryService {
  LaboratoryService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static String? validateName(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return 'Nama laboratorium wajib diisi.';
    if (clean.length > 100) return 'Nama laboratorium maksimal 100 karakter.';
    if (clean.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length < 3) {
      return 'Nama laboratorium minimal memiliki 3 karakter alfanumerik.';
    }
    return null;
  }

  static String? validateCode(String value) {
    final clean = value.trim().toUpperCase();
    if (!RegExp(r'^LAB-[A-Z0-9]+-[0-9]{2}$').hasMatch(clean)) {
      return 'Kode harus mengikuti format LAB-KATEGORI-01.';
    }
    return null;
  }

  /// Mengambil seluruh laboratorium secara realtime.
  Stream<List<Laboratory>> watchLaboratories() {
    return _firestore.collection('laboratories').snapshots().map((snapshot) {
      final laboratories = snapshot.docs.map(Laboratory.fromDocument).toList();

      laboratories.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

      return laboratories;
    });
  }

  /// Mengambil satu laboratorium berdasarkan document ID.
  Future<Laboratory> getLaboratory(String laboratoryId) async {
    final document = await _firestore
        .collection('laboratories')
        .doc(laboratoryId)
        .get();

    if (!document.exists) {
      throw const LaboratoryException('Laboratorium tidak ditemukan.');
    }

    return Laboratory.fromDocument(document);
  }

  /// Membuat laboratorium baru.
  Future<void> createLaboratory({
    required String name,
    required String code,
    required String description,
    required String location,
    required String status,
  }) async {
    final cleanName = name.trim();
    final cleanCode = code.trim().toUpperCase();
    final cleanDescription = description.trim();
    final cleanLocation = location.trim();

    _validateData(
      name: cleanName,
      code: cleanCode,
      location: cleanLocation,
      status: status,
    );

    final existingCode = await _firestore
        .collection('laboratories')
        .where('code', isEqualTo: cleanCode)
        .limit(1)
        .get();

    if (existingCode.docs.isNotEmpty) {
      throw const LaboratoryException('Kode laboratorium sudah digunakan.');
    }

    final document = _firestore.collection('laboratories').doc();

    await document.set({
      'name': cleanName,
      'code': cleanCode,
      'description': cleanDescription,
      'location': cleanLocation,
      'status': status,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Memperbarui data laboratorium.
  ///
  /// Jika [baselineData] diberikan (misalnya dari offline draft atau form edit),
  /// sistem akan melakukan conflict detection dan atomic update menggunakan
  /// Firestore Transaction dengan batas retry yang aman (`maxAttempts: 3`).
  ///
  /// Kompatibel dengan dokumen legacy: field legacy yang tidak diubah tidak akan
  /// menyebabkan kegagalan validasi saat memperbarui field lain yang valid.
  Future<Map<String, Object?>> updateLaboratory({
    required String laboratoryId,
    required String name,
    required String code,
    required String description,
    required String location,
    required String status,
    Map<String, Object?>? baselineData,
    Map<String, ConflictResolutionDecision>? conflictDecisions,
  }) async {
    final cleanName = name.trim();
    final cleanCode = code.trim().toUpperCase();
    final cleanDescription = description.trim();
    final cleanLocation = location.trim();

    if (baselineData != null) {
      return _updateLaboratoryAtomically(
        laboratoryId: laboratoryId,
        localData: <String, Object?>{
          'name': cleanName,
          'code': cleanCode,
          'description': cleanDescription,
          'location': cleanLocation,
          'status': status,
        },
        baselineData: ConflictDetector.normalizeLaboratoryMap(baselineData),
        conflictDecisions: conflictDecisions,
      );
    }

    final reference = _firestore.collection('laboratories').doc(laboratoryId);

    final existingLaboratory = await reference.get();

    if (!existingLaboratory.exists) {
      throw const LaboratoryException('Laboratorium tidak ditemukan.');
    }

    final current = Laboratory.fromDocument(existingLaboratory);
    if (current.name.trim() == cleanName &&
        current.code.trim().toUpperCase() == cleanCode &&
        current.description.trim() == cleanDescription &&
        current.location.trim() == cleanLocation &&
        current.status == status) {
      return const <String, Object?>{};
    }

    _validateUpdatedFields(
      current: current,
      name: cleanName,
      code: cleanCode,
      location: cleanLocation,
      status: status,
    );

    /// Mengecek apakah kode dipakai oleh laboratorium lain.
    if (current.code.trim().toUpperCase() != cleanCode) {
      final existingCode = await _firestore
          .collection('laboratories')
          .where('code', isEqualTo: cleanCode)
          .get();

      final duplicateExists = existingCode.docs.any(
        (document) => document.id != laboratoryId,
      );

      if (duplicateExists) {
        throw const LaboratoryException(
          'Kode laboratorium sudah digunakan oleh laboratorium lain.',
        );
      }
    }

    final update = <String, Object?>{};
    if (current.name.trim() != cleanName) {
      update['name'] = cleanName;
    }
    if (current.code.trim().toUpperCase() != cleanCode) {
      update['code'] = cleanCode;
    }
    if (current.description.trim() != cleanDescription) {
      update['description'] = cleanDescription;
    }
    if (current.location.trim() != cleanLocation) {
      update['location'] = cleanLocation;
    }
    if (current.status != status) {
      update['status'] = status;
    }
    update['updatedAt'] = FieldValue.serverTimestamp();
    await reference.update(update);
    return update;
  }

  Future<Map<String, Object?>> _updateLaboratoryAtomically({
    required String laboratoryId,
    required Map<String, Object?> localData,
    required Map<String, Object?> baselineData,
    Map<String, ConflictResolutionDecision>? conflictDecisions,
  }) async {
    final reference = _firestore.collection('laboratories').doc(laboratoryId);

    // Pre-check di luar transaction untuk mengecek kode unik apabila kode berubah.
    final proposedCode = (localData['code'] as String? ?? '')
        .trim()
        .toUpperCase();
    final baseCode = (baselineData['code'] as String? ?? '')
        .trim()
        .toUpperCase();

    if (proposedCode != baseCode && proposedCode.isNotEmpty) {
      final codeErr = validateCode(proposedCode);
      if (codeErr != null) {
        throw LaboratoryException(codeErr);
      }
      final existingCode = await _firestore
          .collection('laboratories')
          .where('code', isEqualTo: proposedCode)
          .get();
      final duplicateExists = existingCode.docs.any(
        (doc) => doc.id != laboratoryId,
      );
      if (duplicateExists) {
        throw const LaboratoryException(
          'Kode laboratorium sudah digunakan oleh laboratorium lain.',
        );
      }
    }

    try {
      return await _firestore.runTransaction<Map<String, Object?>>(
        (transaction) async {
          final snapshot = await transaction.get(reference);
          if (!snapshot.exists) {
            throw const LaboratoryException('Laboratorium tidak ditemukan.');
          }

          final current = Laboratory.fromDocument(snapshot);
          final serverData = current.toBaselineMap();
          final normalizedLocal = ConflictDetector.normalizeLaboratoryMap(
            localData,
          );

          final analysis = ConflictDetector.analyze(
            baseline: baselineData,
            local: normalizedLocal,
            server: serverData,
            fields: ConflictDetector.laboratoryFields,
          );

          Map<String, Object?> targetValues;
          if (analysis.hasConflict) {
            if (conflictDecisions == null) {
              throw ConflictDetectedException(
                message:
                    'Terdeteksi perubahan pada data laboratorium di server. '
                    'Silakan tinjau dan pilih resolusi konflik.',
                analysis: analysis,
                serverUpdatedAt: current.updatedAt,
              );
            }
            // Pastikan seluruh field yang berkonflik saat ini sudah memiliki keputusan
            // dan nilai server belum berubah lagi sejak pengguna memilih resolusi.
            final missingOrStaleDecision = analysis.hasStaleDecision(
              conflictDecisions,
            );
            if (missingOrStaleDecision) {
              throw ConflictDetectedException(
                message:
                    'Data laboratorium di server kembali berubah saat penyimpanan. '
                    'Silakan tinjau konflik terbaru.',
                analysis: analysis,
                serverUpdatedAt: current.updatedAt,
              );
            }
            targetValues = ConflictDetector.normalizeLaboratoryMap(
              analysis.resolveWithDecisions(conflictDecisions),
            );
          } else {
            // Disjoint changes atau tidak ada perubahan server:
            // pertahankan nilai server untuk field yang tidak diubah lokal.
            targetValues = Map<String, Object?>.from(serverData);
            for (final field in analysis.localChangedFields) {
              targetValues[field] = normalizedLocal[field];
            }
          }

          final finalName = targetValues['name'] as String;
          final finalCode = targetValues['code'] as String;
          final finalDescription = targetValues['description'] as String;
          final finalLocation = targetValues['location'] as String;
          final finalStatus = targetValues['status'] as String;

          _validateUpdatedFields(
            current: current,
            name: finalName,
            code: finalCode,
            location: finalLocation,
            status: finalStatus,
          );

          final update = <String, Object?>{};
          if (current.name.trim() != finalName) {
            update['name'] = finalName;
          }
          if (current.code.trim().toUpperCase() != finalCode) {
            update['code'] = finalCode;
          }
          if (current.description.trim() != finalDescription) {
            update['description'] = finalDescription;
          }
          if (current.location.trim() != finalLocation) {
            update['location'] = finalLocation;
          }
          if (current.status != finalStatus) {
            update['status'] = finalStatus;
          }

          if (update.isEmpty) {
            return const <String, Object?>{};
          }

          update['updatedAt'] = FieldValue.serverTimestamp();
          transaction.update(reference, update);
          return update;
        },
        maxAttempts: 3,
      );
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw const LaboratoryException(
          'Akses ditolak. Pastikan Anda memiliki izin Superadmin aktif.',
        );
      }
      if (error.code == 'unavailable' || error.code == 'deadline-exceeded') {
        throw const LaboratoryException(
          'Koneksi internet tidak stabil. Draft tetap tersimpan secara lokal.',
        );
      }
      throw LaboratoryException(
        'Gagal menyimpan perubahan laboratorium (${error.code}).',
      );
    }
  }

  void _validateUpdatedFields({
    required Laboratory current,
    required String name,
    required String code,
    required String location,
    required String status,
  }) {
    // Validasi nama wajib jika nama diubah atau nama baru tidak kosong.
    if (name != current.name.trim()) {
      final nameError = validateName(name);
      if (nameError != null) throw LaboratoryException(nameError);
    } else if (name.isEmpty) {
      throw const LaboratoryException('Nama laboratorium wajib diisi.');
    }

    // Kompatibilitas data legacy: jika kode legacy tidak diubah, izinkan tetap
    // dipertahankan. Jika kode diubah, wajib mengikuti format standar terbaru.
    if (code != current.code.trim().toUpperCase()) {
      final codeError = validateCode(code);
      if (codeError != null) throw LaboratoryException(codeError);
    } else if (code.isEmpty) {
      throw const LaboratoryException('Kode laboratorium wajib diisi.');
    }

    // Jika lokasi diubah (atau diisi), lokasi tidak boleh kosong.
    if (location != current.location.trim() && location.isEmpty) {
      throw const LaboratoryException('Lokasi laboratorium wajib diisi.');
    }

    if (status != 'active' && status != 'inactive') {
      throw const LaboratoryException('Status laboratorium tidak valid.');
    }
  }

  /// Menghapus laboratorium secara permanen.
  ///
  /// Hard-delete hanya diperbolehkan jika laboratorium
  /// belum pernah mempunyai membership.
  Future<void> deleteLaboratory(String laboratoryId) async {
    final laboratoryReference = _firestore
        .collection('laboratories')
        .doc(laboratoryId);

    final laboratory = await laboratoryReference.get();

    if (!laboratory.exists) {
      throw const LaboratoryException('Laboratorium tidak ditemukan.');
    }

    /// Cek relasi membership, termasuk membership
    /// yang sudah tidak aktif.
    final membershipQuery = await _firestore
        .collection('lab_memberships')
        .where('labId', isEqualTo: laboratoryId)
        .limit(1)
        .get();

    if (membershipQuery.docs.isNotEmpty) {
      throw const LaboratoryException(
        'Laboratorium sudah memiliki riwayat membership dan tidak dapat '
        'dihapus permanen. Ubah status menjadi Tidak Aktif.',
      );
    }

    await laboratoryReference.delete();
  }

  void _validateData({
    required String name,
    required String code,
    required String location,
    required String status,
  }) {
    final nameError = validateName(name);
    if (nameError != null) throw LaboratoryException(nameError);
    final codeError = validateCode(code);
    if (codeError != null) throw LaboratoryException(codeError);

    if (location.isEmpty) {
      throw const LaboratoryException('Lokasi laboratorium wajib diisi.');
    }

    if (status != 'active' && status != 'inactive') {
      throw const LaboratoryException('Status laboratorium tidak valid.');
    }
  }
}

class LaboratoryException implements Exception {
  const LaboratoryException(this.message);

  final String message;

  @override
  String toString() => message;
}
