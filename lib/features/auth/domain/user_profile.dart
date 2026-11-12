import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.email,
    required this.fullName,
    required this.role,
    required this.status,
    this.profilePhotoUrl,
    this.phoneNumber,
    this.nim,
    this.studyProgram,
    this.semester,
    this.nip,
    this.nidn,
    this.pendingEmail,
    this.emailChangeStatus,
  });

  final String uid;
  final String email;
  final String fullName;
  final String role;
  final String status;
  final String? profilePhotoUrl;
  final String? phoneNumber;
  final String? nim;
  final String? studyProgram;
  final int? semester;
  final String? nip;
  final String? nidn;
  final String? pendingEmail;
  final String? emailChangeStatus;

  bool get isActive => status == 'active';

  bool get isSuperadmin => role == 'superadmin';

  bool get isLabAdmin => role == 'lab_admin';

  bool get isStudent => role == 'student';

  bool get hasPendingEmailChange =>
      pendingEmail != null &&
      pendingEmail!.trim().isNotEmpty &&
      (emailChangeStatus == 'pending' || emailChangeStatus == 'sent');

  factory UserProfile.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();

    if (data == null) {
      throw const FormatException('Data profil pengguna tidak ditemukan.');
    }

    return UserProfile.fromData(document.id, data);
  }

  factory UserProfile.fromData(String uid, Map<String, dynamic> data) {
    return UserProfile(
      uid: uid,
      email: data['email'] as String? ?? '',
      fullName: data['fullName'] as String? ?? '',
      role: data['role'] as String? ?? '',
      status: data['status'] as String? ?? '',
      profilePhotoUrl: data['profilePhotoUrl'] as String?,
      phoneNumber: data['phoneNumber'] as String?,
      nim: data['nim'] as String?,
      studyProgram: data['studyProgram'] as String?,
      semester: data['semester'] as int?,
      nip: data['nip'] as String?,
      nidn: data['nidn'] as String?,
      pendingEmail: data['pendingEmail'] as String?,
      emailChangeStatus: data['emailChangeStatus'] as String?,
    );
  }
}
