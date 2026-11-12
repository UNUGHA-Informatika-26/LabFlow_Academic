import 'package:cloud_firestore/cloud_firestore.dart';

class EmailChangeRequest {
  const EmailChangeRequest({
    required this.id,
    required this.uid,
    required this.currentEmail,
    required this.requestedEmail,
    required this.reason,
    required this.status,
    required this.requestedAt,
    this.reviewedAt,
    this.reviewedBy,
    this.rejectionReason,
    this.completedAt,
  });

  final String id;
  final String uid;
  final String currentEmail;
  final String requestedEmail;
  final String reason;
  final String status; // 'pending' | 'approved' | 'rejected' | 'completed'
  final DateTime requestedAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;
  final String? rejectionReason;
  final DateTime? completedAt;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isCompleted => status == 'completed';

  factory EmailChangeRequest.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return EmailChangeRequest.fromMap(doc.id, data);
  }

  factory EmailChangeRequest.fromMap(String id, Map<String, dynamic> data) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return EmailChangeRequest(
      id: id,
      uid: data['uid'] as String? ?? '',
      currentEmail: data['currentEmail'] as String? ?? '',
      requestedEmail: data['requestedEmail'] as String? ?? '',
      reason: data['reason'] as String? ?? '',
      status: data['status'] as String? ?? 'pending',
      requestedAt: parseDate(data['requestedAt']),
      reviewedAt: data['reviewedAt'] != null ? parseDate(data['reviewedAt']) : null,
      reviewedBy: data['reviewedBy'] as String?,
      rejectionReason: data['rejectionReason'] as String?,
      completedAt: data['completedAt'] != null ? parseDate(data['completedAt']) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'currentEmail': currentEmail,
      'requestedEmail': requestedEmail,
      'reason': reason,
      'status': status,
      'requestedAt': Timestamp.fromDate(requestedAt),
      if (reviewedAt != null) 'reviewedAt': Timestamp.fromDate(reviewedAt!),
      if (reviewedBy != null) 'reviewedBy': reviewedBy,
      if (rejectionReason != null) 'rejectionReason': rejectionReason,
      if (completedAt != null) 'completedAt': Timestamp.fromDate(completedAt!),
    };
  }
}
