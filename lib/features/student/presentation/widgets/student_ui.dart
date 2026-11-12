import 'package:flutter/material.dart';

import '../../domain/student_models.dart';

const studentPaper = Color(0xFFF6F9EF);
const studentInk = Color(0xFF111111);
const studentLime = Color(0xFFB9F33D);
const studentSoftLime = Color(0xFFEAFBCB);
const studentBorder = Color(0xFFDDE2D5);
const studentMuted = Color(0xFF737A70);
const studentBlueSoft = Color(0xFFDDEAFE);
const studentBlueText = Color(0xFF2C5CA8);
const studentPinkSoft = Color(0xFFFCE2DF);
const studentPinkText = Color(0xFFD14334);
const studentOrangeSoft = Color(0xFFFFE8C4);
const studentOrangeText = Color(0xFFA56600);

class StudentPageTitle extends StatelessWidget {
  const StudentPageTitle({required this.title, this.subtitle, super.key});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 27,
            height: 1.05,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            color: studentInk,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 7),
          Text(
            subtitle!,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: studentMuted,
            ),
          ),
        ],
      ],
    );
  }
}

class StudentBackHeader extends StatelessWidget {
  const StudentBackHeader({
    required this.title,
    required this.onBack,
    this.trailing,
    super.key,
  });

  final String title;
  final VoidCallback onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InkWell(
          onTap: onBack,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.arrow_back_rounded, color: studentInk),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: studentInk,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class StudentStatusPill extends StatelessWidget {
  const StudentStatusPill({
    required this.status,
    this.small = false,
    super.key,
  });

  final String status;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 8 : 11,
        vertical: small ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: studentStatusBackground(status),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        studentStatusLabel(status),
        style: TextStyle(
          fontSize: small ? 9 : 12,
          fontWeight: FontWeight.w900,
          color: studentStatusForeground(status),
        ),
      ),
    );
  }
}

class StudentLoading extends StatelessWidget {
  const StudentLoading({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Memuat',
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w900,
                color: studentInk,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              height: 150,
              decoration: BoxDecoration(
                color: const Color(0xFFDDE3D4),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const SizedBox(height: 14),
            ...List.generate(
              3,
              (index) => Padding(
                padding: const EdgeInsets.only(bottom: 13),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDDE3D4),
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 10,
                            decoration: BoxDecoration(
                              color: const Color(0xFFDDE3D4),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          const SizedBox(height: 9),
                          FractionallySizedBox(
                            widthFactor: .55,
                            child: Container(
                              height: 9,
                              decoration: BoxDecoration(
                                color: const Color(0xFFDDE3D4),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: studentInk,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(fontSize: 12, color: studentMuted),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class StudentErrorState extends StatelessWidget {
  const StudentErrorState({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const StudentPageTitle(title: 'Koneksi'),
            const SizedBox(height: 22),
            Container(
              width: double.infinity,
              height: 210,
              decoration: BoxDecoration(
                color: studentSoftLime,
                borderRadius: BorderRadius.circular(24),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.cloud_off_rounded,
                size: 70,
                color: studentInk,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: studentPinkSoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Perlu perhatian',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: studentPinkText,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Koneksi bermasalah',
              style: TextStyle(
                fontSize: 25,
                height: 1.05,
                fontWeight: FontWeight.w900,
                color: studentInk,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              message,
              style: const TextStyle(
                fontSize: 14,
                height: 1.45,
                color: studentMuted,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: studentInk,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                ),
                child: const Text(
                  'Coba Lagi',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StudentAssetCard extends StatelessWidget {
  const StudentAssetCard({
    required this.asset,
    required this.labName,
    required this.onTap,
    this.compact = false,
    super.key,
  });

  final StudentAsset asset;
  final String labName;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final imageUrl = asset.imageUrl;

    if (compact) {
      return Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 74,
                    height: 74,
                    child: _assetImage(imageUrl),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        asset.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: studentInk,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${asset.code} · $labName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: studentMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      StudentStatusPill(
                        status: asset.isAvailable ? 'available' : asset.status,
                        small: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: studentBorder),
            borderRadius: BorderRadius.circular(18),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(aspectRatio: 1.6, child: _assetImage(imageUrl)),
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 10, 11, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StudentStatusPill(
                      status: asset.isAvailable ? 'available' : asset.status,
                      small: true,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      asset.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      asset.code,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: studentMuted),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      labName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: studentMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _assetImage(String? imageUrl) {
    return Container(
      color: studentSoftLime,
      child: imageUrl != null && imageUrl.isNotEmpty
          ? Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const _AssetPlaceholder(),
            )
          : const _AssetPlaceholder(),
    );
  }
}

class _AssetPlaceholder extends StatelessWidget {
  const _AssetPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(Icons.memory_rounded, size: 42, color: studentInk),
    );
  }
}

String studentStatusLabel(String value) {
  switch (value) {
    case 'available':
      return 'Tersedia';
    case 'borrowed':
      return 'Dipinjam';
    case 'maintenance':
      return 'Maintenance';
    case 'pending':
      return 'Menunggu';
    case 'approved':
      return 'Disetujui';
    case 'waiting_pickup':
      return 'Menunggu Diambil';
    case 'active':
      return 'Aktif';
    case 'returned':
      return 'Dikembalikan';
    case 'rejected':
      return 'Ditolak';
    case 'cancelled':
      return 'Dibatalkan';
    case 'open':
      return 'Menunggu';
    case 'acknowledged':
      return 'Diterima';
    case 'in_progress':
      return 'Sedang Diproses';
    case 'resolved':
      return 'Selesai';
    case 'closed':
      return 'Ditutup';
    default:
      return value;
  }
}

String studentCategoryLabel(String value) {
  switch (value) {
    case 'asset_damage':
      return 'Kerusakan Aset';
    case 'asset_lost':
      return 'Aset Hilang';
    case 'network':
      return 'Jaringan';
    case 'computer':
      return 'Komputer';
    case 'software':
      return 'Software';
    case 'facility':
      return 'Fasilitas';
    case 'electricity':
      return 'Kelistrikan';
    case 'other':
      return 'Lainnya';
    default:
      return value;
  }
}

String studentPriorityLabel(String value) {
  switch (value) {
    case 'low':
      return 'Prioritas Rendah';
    case 'medium':
      return 'Prioritas Sedang';
    case 'high':
      return 'Prioritas Tinggi';
    case 'critical':
      return 'Prioritas Mendesak';
    default:
      return value;
  }
}

Color studentStatusBackground(String value) {
  switch (value) {
    case 'available':
    case 'active':
    case 'returned':
    case 'resolved':
      return studentSoftLime;
    case 'borrowed':
    case 'acknowledged':
    case 'in_progress':
      return studentBlueSoft;
    case 'maintenance':
    case 'pending':
      return studentOrangeSoft;
    case 'rejected':
    case 'cancelled':
      return studentPinkSoft;
    default:
      return const Color(0xFFF0F1ED);
  }
}

Color studentStatusForeground(String value) {
  switch (value) {
    case 'borrowed':
    case 'acknowledged':
    case 'in_progress':
      return studentBlueText;
    case 'maintenance':
    case 'pending':
      return studentOrangeText;
    case 'rejected':
    case 'cancelled':
      return studentPinkText;
    default:
      return studentInk;
  }
}

Color studentPriorityBackground(String value) {
  switch (value) {
    case 'high':
    case 'critical':
      return studentPinkSoft;
    default:
      return const Color(0xFFF0F1ED);
  }
}

Color studentPriorityForeground(String value) {
  switch (value) {
    case 'high':
    case 'critical':
      return studentPinkText;
    default:
      return studentMuted;
  }
}

String studentFormatDate(DateTime value) {
  if (value.millisecondsSinceEpoch == 0) return '-';

  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];

  return '${value.day} ${months[value.month - 1]} ${value.year}';
}

String studentFormatDateTime(DateTime value) {
  if (value.millisecondsSinceEpoch == 0) return '-';
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '${studentFormatDate(value)} · $hour.$minute';
}

double studentAssetGridAspectRatio(double textScale) {
  final extra = (textScale - 1).clamp(0.0, 1.0);
  return .70 / (1 + extra * .6);
}
