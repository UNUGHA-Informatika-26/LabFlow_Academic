import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:labflow/features/student/data/student_report_service.dart';
import 'package:labflow/features/student/domain/student_models.dart';
import 'package:labflow/features/student/presentation/cubit/student_report_create_cubit.dart';
import 'package:labflow/features/student/presentation/pages/student_report_create_page.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/fake_firestore.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _FakeStudentReportService extends StudentReportService {
  _FakeStudentReportService()
      : super(
          firestore: FakeMemoryFirestore(),
          auth: _MockFirebaseAuth(),
        );

  @override
  Future<List<StudentLaboratory>> loadLaboratories() async {
    return [
      const StudentLaboratory(
        id: 'lab-1',
        name: 'Laboratorium Rekayasa Perangkat Lunak & Sistem Terdistribusi Sangat Panjang Sekali',
        code: 'LAB-RPL-001',
        location: 'Gedung B Lantai 3',
      ),
      const StudentLaboratory(
        id: 'lab-2',
        name: 'Lab Komputasi Dasar',
        code: 'LAB-KOM-002',
        location: 'Gedung A Lantai 1',
      ),
    ];
  }

  @override
  Future<List<StudentAsset>> loadAssets(String labId) async {
    return [
      const StudentAsset(
        id: 'asset-1',
        labId: 'lab-1',
        name: 'Workstation Server Intel Xeon 64-Core Dual Socket Enterprise Edition Extreme',
        code: 'WS-RPL-SRV-2026-X01',
        category: 'computer',
        description: 'Server performa tinggi untuk komputasi dan riset',
        location: 'Rak Server Utama Ruang 301',
        stock: 5,
        status: 'available',
        condition: 'good',
        qrValue: 'QR-WS-001',
      ),
    ];
  }
}

void main() {
  const viewports = <String, Size>{
    '360x800': Size(360, 800),
    '393x873': Size(393, 873),
    '412x915': Size(412, 915),
  };

  for (final entry in viewports.entries) {
    testWidgets(
      'StudentReportCreatePage renders cleanly without RenderFlex overflow on ${entry.key}',
      (tester) async {
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final cubit = StudentReportCreateCubit(_FakeStudentReportService());
        await cubit.load();

        await tester.pumpWidget(
          MaterialApp(
            home: StudentReportCreatePage(cubit: cubit),
          ),
        );
        await tester.pumpAndSettle();

        // Verifikasi tidak ada exception / overflow error
        expect(tester.takeException(), isNull);

        // Verifikasi judul halaman
        expect(find.text('Buat Laporan'), findsOneWidget);

        // Verifikasi dropdown dapat memuat data panjang tanpa overflow
        expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(4));

        // Scroll ke bawah untuk melihat tombol submit
        await tester.drag(find.byType(ListView), const Offset(0, -400));
        await tester.pumpAndSettle();

        expect(find.text('Kirim Laporan'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'StudentReportCreatePage remains responsive with keyboard open on ${entry.key}',
      (tester) async {
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1.0;
        // Simulate bottom inset (software keyboard)
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);

        final cubit = StudentReportCreateCubit(_FakeStudentReportService());
        await cubit.load();

        await tester.pumpWidget(
          MaterialApp(
            home: StudentReportCreatePage(cubit: cubit),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        // Masukkan teks panjang ke judul dan deskripsi
        final titleField = find.widgetWithText(TextField, 'Jaringan Tidak Tersambung');
        expect(titleField, findsOneWidget);
        await tester.enterText(
          titleField,
          'Masalah koneksi kabel switch lantai 3 terputus mendadak saat praktikum berlangsung',
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  }
}
