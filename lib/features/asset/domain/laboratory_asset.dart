import 'package:cloud_firestore/cloud_firestore.dart';

class LaboratoryAsset {
  const LaboratoryAsset({
    required this.id,
    required this.labId,
    required this.code,
    required this.name,
    required this.category,
    required this.description,
    required this.location,
    required this.stock,
    required this.status,
    required this.condition,
    required this.qrValue,
    this.imageUrl = '',
    this.updatedAt,
  });

  final String id;
  final String labId;
  final String code;
  final String name;
  final String category;
  final String description;
  final String location;
  final int stock;
  final String status;
  final String condition;
  final String qrValue;
  final String imageUrl;
  final DateTime? updatedAt;

  bool get isAvailable => status == 'available';

  bool get isBorrowed => status == 'borrowed';

  bool get isInMaintenance => status == 'maintenance';

  bool get isInactive => status == 'inactive';

  bool get isGoodCondition => condition == 'good';

  bool get hasDamage => condition == 'minor_damage' || condition == 'damaged';

  bool get hasStock => stock > 0;

  bool get hasImage => imageUrl.trim().isNotEmpty;

  Map<String, Object?> toBaselineMap() => {
    'code': code.trim().toUpperCase(),
    'name': name.trim(),
    'category': category.trim(),
    'description': description.trim(),
    'location': location.trim(),
    'stock': stock,
    'status': status,
    'condition': condition,
    'imageUrl': imageUrl.trim(),
  };

  LaboratoryAsset copyWith({
    String? id,
    String? labId,
    String? code,
    String? name,
    String? category,
    String? description,
    String? location,
    int? stock,
    String? status,
    String? condition,
    String? qrValue,
    String? imageUrl,
    DateTime? updatedAt,
  }) {
    return LaboratoryAsset(
      id: id ?? this.id,
      labId: labId ?? this.labId,
      code: code ?? this.code,
      name: name ?? this.name,
      category: category ?? this.category,
      description: description ?? this.description,
      location: location ?? this.location,
      stock: stock ?? this.stock,
      status: status ?? this.status,
      condition: condition ?? this.condition,
      qrValue: qrValue ?? this.qrValue,
      imageUrl: imageUrl ?? this.imageUrl,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory LaboratoryAsset.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();

    if (data == null) {
      throw const FormatException('Data aset laboratorium tidak ditemukan.');
    }

    final rawUpdatedAt = data['updatedAt'];
    final updatedAt = switch (rawUpdatedAt) {
      final Timestamp timestamp => timestamp.toDate().toUtc(),
      final DateTime dateTime => dateTime.toUtc(),
      final String isoString => DateTime.tryParse(isoString)?.toUtc(),
      _ => null,
    };

    return LaboratoryAsset(
      id: document.id,
      labId: data['labId'] as String? ?? '',
      code: data['code'] as String? ?? '',
      name: data['name'] as String? ?? '',
      category: data['category'] as String? ?? '',
      description: data['description'] as String? ?? '',
      location: data['location'] as String? ?? '',

      // Backward-compatible untuk aset lama yang dibuat
      // sebelum field stock diperkenalkan.
      stock: data['stock'] as int? ?? 1,

      status: data['status'] as String? ?? '',
      condition: data['condition'] as String? ?? '',
      qrValue: data['qrValue'] as String? ?? '',

      // Backward-compatible untuk aset lama yang dibuat
      // sebelum dukungan foto aset diperkenalkan.
      imageUrl: data['imageUrl'] as String? ?? '',
      updatedAt: updatedAt,
    );
  }
}
