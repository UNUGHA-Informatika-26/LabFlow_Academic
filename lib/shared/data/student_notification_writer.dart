/// Penulis notifikasi legacy.
/// 
/// Pada arsitektur Firebase Spark Plan, seluruh koleksi `notifications`
/// dilindungi oleh Firestore Security Rules (`allow create: if false;`),
/// sehingga penulisan langsung dari sisi client dilarang.
///
/// Seluruh fitur notifikasi aktif LabFlow kini dilayani langsung oleh
/// [NotificationCenterService] melalui stream realtime domain `borrow_requests`
/// dan `reports`. File ini dinonaktifkan secara aman tanpa memicu kegagalan permission.
class StudentNotificationWriter {
  const StudentNotificationWriter();

  Future<void> borrowing(String requestId, String type) async {
    // Dinonaktifkan: Notifikasi ditangani secara realtime oleh NotificationCenterService
  }

  Future<void> report(
    String reportId, {
    bool message = false,
    bool imageOnly = false,
  }) async {
    // Dinonaktifkan: Notifikasi ditangani secara realtime oleh NotificationCenterService
  }
}
