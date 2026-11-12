import 'dart:convert';
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class AdminCredentialService {
  AdminCredentialService({
    FirebaseAuth? firebaseAuth,
    http.Client? client,
    String? baseUrl,
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _client = client ?? http.Client(),
       _resolvedBaseUrl = baseUrl ?? resolveDefaultBaseUrl();

  static const String envKey = 'LABFLOW_ENV';
  static const String emulatorHostKey = 'FUNCTIONS_EMULATOR_HOST';
  static const String emulatorPortKey = 'FUNCTIONS_EMULATOR_PORT';
  static const String regionKey = 'FUNCTIONS_REGION';
  static const String projectIdKey = 'FIREBASE_PROJECT_ID';

  static const String productionBaseUrl =
      'https://us-central1-labflow-academic-2026.cloudfunctions.net';

  final FirebaseAuth _firebaseAuth;
  final http.Client _client;
  final String _resolvedBaseUrl;

  String get baseUrl => _resolvedBaseUrl;

  /// Menyelesaikan base URL Cloud Functions berdasarkan variabel lingkungan kompilasi.
  static String resolveDefaultBaseUrl() {
    return resolveBaseUrl(
      env: const String.fromEnvironment(envKey, defaultValue: 'production'),
      emulatorHost: const String.fromEnvironment(
        emulatorHostKey,
        defaultValue: '10.0.2.2',
      ),
      emulatorPort: const int.fromEnvironment(
        emulatorPortKey,
        defaultValue: 18081,
      ),
      region: const String.fromEnvironment(
        regionKey,
        defaultValue: 'us-central1',
      ),
      projectId: const String.fromEnvironment(
        projectIdKey,
        defaultValue: 'labflow-academic-2026',
      ),
      customBaseUrl: const String.fromEnvironment('FUNCTIONS_BASE_URL'),
    );
  }

  /// Memetakan konfigurasi environment menjadi endpoint Cloud Functions yang valid.
  static String resolveBaseUrl({
    String env = 'production',
    String emulatorHost = '10.0.2.2',
    int emulatorPort = 18081,
    String region = 'us-central1',
    String projectId = 'labflow-academic-2026',
    String? customBaseUrl,
  }) {
    if (customBaseUrl != null && customBaseUrl.trim().isNotEmpty) {
      return customBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    }

    final normalizedEnv = env.trim().toLowerCase();
    switch (normalizedEnv) {
      case 'emulator':
      case 'local':
        final cleanHost = emulatorHost.trim();
        if (cleanHost.isEmpty || emulatorPort <= 0 || emulatorPort > 65535) {
          throw const AdminCredentialException(
            'Konfigurasi Functions Emulator tidak valid (host atau port tidak tersedia).',
            code: 'invalid-emulator-config',
          );
        }
        final cleanProject = projectId.trim();
        final cleanRegion = region.trim();
        if (cleanProject.isEmpty || cleanRegion.isEmpty) {
          throw const AdminCredentialException(
            'Konfigurasi Functions Emulator tidak valid (project ID atau region tidak tersedia).',
            code: 'invalid-emulator-config',
          );
        }
        return 'http://$cleanHost:$emulatorPort/$cleanProject/$cleanRegion';

      case 'staging':
        final cleanProject = projectId.trim();
        final cleanRegion = region.trim();
        return 'https://$cleanRegion-$cleanProject.cloudfunctions.net';

      case 'production':
        return productionBaseUrl;

      default:
        throw AdminCredentialException(
          'Konfigurasi environment Cloud Functions tidak valid ($env).',
          code: 'invalid-env-config',
        );
    }
  }

  Future<void> requestEmailChange({
    required String targetUid,
    required String newEmail,
  }) => _call('adminRequestEmailChange', {
    'targetUid': targetUid,
    'newEmail': newEmail.trim().toLowerCase(),
  });

  Future<void> sendPasswordReset({required String targetUid}) =>
      _call('adminSendPasswordReset', {'targetUid': targetUid});

  Future<void> _call(String functionName, Map<String, dynamic> data) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw const AdminCredentialException('Sesi Superadmin tidak ditemukan.');
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const AdminCredentialException('Token autentikasi tidak tersedia.');
    }

    late final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_resolvedBaseUrl/$functionName'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'data': data}),
          )
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const AdminCredentialException(
        'Operasi kredensial membutuhkan koneksi server dan waktunya habis.',
      );
    } on http.ClientException {
      throw const AdminCredentialException(
        'Operasi kredensial tidak tersedia saat offline.',
      );
    }

    Map<String, dynamic>? payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      payload = null;
    }
    final error = payload?['error'];
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        error != null) {
      final message = error is Map<String, dynamic>
          ? error['message']?.toString()
          : null;
      throw AdminCredentialException(
        _safeMessage(message),
        code: error is Map<String, dynamic>
            ? error['status']?.toString()
            : null,
      );
    }
  }

  String _safeMessage(String? message) {
    const allowed = {
      'Hanya Superadmin aktif yang diizinkan.',
      'Pengguna tidak ditemukan.',
      'Email tersebut sudah digunakan oleh akun lain.',
      'Format email tidak valid.',
      'Sesi Superadmin tidak ditemukan.',
      'Pengiriman email autentikasi belum dikonfigurasi.',
      'Konfigurasi tautan autentikasi belum tersedia.',
      'Gunakan Forgot Password untuk akun sendiri.',
      'Superadmin tidak dapat mengubah email sendiri melalui User Management.',
      'Operasi kredensial tidak tersedia saat offline.',
      'Operasi kredensial membutuhkan koneksi server dan waktunya habis.',
      'Email baru sama dengan email saat ini.',
      'Permintaan perubahan email masih diproses.',
      'Terlalu banyak permintaan. Coba lagi nanti.',
      'Akun target tidak memiliki email.',
      'Akun target tidak memiliki email saat ini.',
      'Akun autentikasi pengguna tidak ditemukan.',
      'UID pengguna tidak valid.',
      'Autentikasi diperlukan.',
      'Email autentikasi gagal dikirim.',
      'Kode verifikasi email tidak tersedia.',
      'Tautan verifikasi tidak valid.',
      'Tautan verifikasi sudah tidak berlaku.',
      'Tautan verifikasi kedaluwarsa atau sudah digunakan.',
      'Verifikasi email tidak dapat dikonfirmasi.',
    };
    return allowed.contains(message)
        ? message!
        : 'Permintaan kredensial tidak dapat diproses.';
  }
}

class AdminCredentialException implements Exception {
  const AdminCredentialException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}
