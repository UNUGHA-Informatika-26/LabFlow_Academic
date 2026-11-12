import 'package:cloud_firestore/cloud_firestore.dart';

class Laboratory {
  const Laboratory({
    required this.id,
    required this.name,
    required this.code,
    required this.description,
    required this.location,
    required this.status,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String code;
  final String description;
  final String location;
  final String status;
  final DateTime? updatedAt;

  bool get isActive => status == 'active';

  Map<String, Object?> toBaselineMap() => {
    'name': name.trim(),
    'code': code.trim().toUpperCase(),
    'description': description.trim(),
    'location': location.trim(),
    'status': status,
  };

  Laboratory copyWith({
    String? id,
    String? name,
    String? code,
    String? description,
    String? location,
    String? status,
    DateTime? updatedAt,
  }) {
    return Laboratory(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      description: description ?? this.description,
      location: location ?? this.location,
      status: status ?? this.status,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Laboratory.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();

    if (data == null) {
      throw const FormatException('Data laboratorium tidak ditemukan.');
    }

    final rawUpdatedAt = data['updatedAt'];
    final updatedAt = switch (rawUpdatedAt) {
      final Timestamp timestamp => timestamp.toDate().toUtc(),
      final DateTime dateTime => dateTime.toUtc(),
      final String isoString => DateTime.tryParse(isoString)?.toUtc(),
      _ => null,
    };

    return Laboratory(
      id: document.id,
      name: data['name'] as String? ?? '',
      code: data['code'] as String? ?? '',
      description: data['description'] as String? ?? '',
      location: data['location'] as String? ?? '',
      status: data['status'] as String? ?? '',
      updatedAt: updatedAt,
    );
  }
}
