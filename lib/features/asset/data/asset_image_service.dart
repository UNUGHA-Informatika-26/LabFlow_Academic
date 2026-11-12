import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class AssetImageService {
  AssetImageService({
    ImagePicker? imagePicker,
    http.Client? httpClient,
    String? cloudName,
    String? uploadPreset,
  })  : _imagePicker = imagePicker ?? ImagePicker(),
        _httpClient = httpClient ?? _sharedClient,
        _configuredCloudName = cloudName,
        _configuredUploadPreset = uploadPreset;

  static final http.Client _sharedClient = http.Client();

  final ImagePicker _imagePicker;
  final http.Client _httpClient;
  final String? _configuredCloudName;
  final String? _configuredUploadPreset;

  static const String _cloudName = String.fromEnvironment(
    'CLOUDINARY_CLOUD_NAME',
    defaultValue: 'uaorce9b',
  );
  static const String _uploadPreset = String.fromEnvironment(
    'CLOUDINARY_UPLOAD_PRESET',
    defaultValue: 'labflow_assets',
  );

  String get effectiveCloudName =>
      (_configuredCloudName?.trim().isNotEmpty ?? false)
          ? _configuredCloudName!.trim()
          : _cloudName.trim();

  String get effectiveUploadPreset =>
      (_configuredUploadPreset?.trim().isNotEmpty ?? false)
          ? _configuredUploadPreset!.trim()
          : _uploadPreset.trim();

  /// Memilih satu foto aset dari galeri perangkat.
  Future<XFile?> pickFromGallery() async {
    return _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
      maxHeight: 1600,
      requestFullMetadata: false,
    );
  }

  /// Mengunggah foto aset ke Cloudinary.
  ///
  /// Hanya secure URL yang akan disimpan ke Firestore.
  Future<String> uploadAssetImage({
    required XFile image,
    required String laboratoryId,
  }) async {
    return (await uploadImage(
      image: image,
      folder: 'labflow/assets/$laboratoryId',
      maximumBytes: 5 * 1024 * 1024,
    )).secureUrl;
  }

  Future<CloudinaryImageUpload> uploadImage({
    required XFile image,
    required String folder,
    int maximumBytes = 10 * 1024 * 1024,
  }) async {
    _validateConfiguration();

    final file = File(image.path);
    if (!await file.exists()) {
      throw const AssetImageException(
        'File gambar yang dipilih tidak ditemukan.',
      );
    }

    final fileSize = await file.length();
    if (fileSize <= 0) {
      throw const AssetImageException('File gambar kosong atau tidak valid.');
    }

    if (fileSize > maximumBytes) {
      throw AssetImageException(
        'Ukuran gambar maksimal ${maximumBytes ~/ (1024 * 1024)} MB.',
      );
    }

    final extension = _fileExtension(image.name);
    if (!_allowedExtensions.contains(extension)) {
      throw const AssetImageException(
        'Format gambar harus JPG, JPEG, PNG, atau WEBP.',
      );
    }

    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$effectiveCloudName/image/upload',
    );

    final request = http.MultipartRequest('POST', uri);
    request.fields['upload_preset'] = effectiveUploadPreset;
    request.fields['folder'] = folder;
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        image.path,
        filename: image.name,
      ),
    );

    http.StreamedResponse response;
    try {
      response = await _httpClient
          .send(request)
          .timeout(const Duration(seconds: 30));
    } on SocketException {
      throw const AssetImageException('Tidak dapat terhubung ke Cloudinary.');
    } on TimeoutException {
      throw const AssetImageException(
        'Upload melewati batas waktu. Coba lagi.',
      );
    } on HttpException {
      throw const AssetImageException('Upload gambar gagal diproses.');
    } catch (_) {
      throw const AssetImageException('Upload gambar gagal. Coba lagi.');
    }

    String responseBody;
    try {
      responseBody = await response.stream.bytesToString().timeout(
        const Duration(seconds: 30),
      );
    } on TimeoutException {
      throw const AssetImageException(
        'Upload melewati batas waktu. Coba lagi.',
      );
    }

    Map<String, dynamic>? data;
    try {
      data = jsonDecode(responseBody) as Map<String, dynamic>;
    } catch (_) {
      data = null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 413) {
        throw const AssetImageException('Ukuran gambar melebihi batas.');
      }
      if (response.statusCode == 400 ||
          response.statusCode == 401 ||
          response.statusCode == 403) {
        throw const AssetImageException(
          'Cloudinary menolak konfigurasi upload. Periksa upload preset unsigned.',
        );
      }
      throw AssetImageException(
        'Cloudinary gagal menerima gambar (HTTP ${response.statusCode}).',
      );
    }

    final secureUrl = data?['secure_url'] as String?;
    if (secureUrl == null || secureUrl.trim().isEmpty) {
      throw const AssetImageException(
        'URL gambar tidak diterima dari Cloudinary.',
      );
    }

    return CloudinaryImageUpload(
      secureUrl: secureUrl.trim(),
      publicId: (data?['public_id'] as String?)?.trim(),
    );
  }

  void _validateConfiguration() {
    if (effectiveCloudName.isEmpty || effectiveUploadPreset.isEmpty) {
      throw const AssetImageException('Konfigurasi upload belum tersedia.');
    }
  }

  String _fileExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == fileName.length - 1) {
      return '';
    }

    return fileName.substring(dotIndex + 1).toLowerCase();
  }

  static const Set<String> _allowedExtensions = {'jpg', 'jpeg', 'png', 'webp'};
}

class AssetImageException implements Exception {
  const AssetImageException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CloudinaryImageUpload {
  const CloudinaryImageUpload({required this.secureUrl, this.publicId});
  final String secureUrl;
  final String? publicId;
}
