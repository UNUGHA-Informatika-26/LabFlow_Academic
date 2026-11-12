import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:labflow/features/auth/presentation/pages/forgot_password_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestWidget() => const MaterialApp(
    home: ForgotPasswordPage(),
  );

  group('ForgotPasswordPage (Bantuan Akses Akun)', () {
    testWidgets('renders all expected texts, template, and buttons', (tester) async {
      tester.view.physicalSize = const Size(393, 873);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Bantuan Akses Akun'), findsOneWidget);
      expect(find.text('Prosedur Pemulihan Terkelola'), findsOneWidget);
      expect(
        find.textContaining('Hubungi Superadmin untuk mendapatkan bantuan pemulihan akun'),
        findsOneWidget,
      );
      expect(find.text('Template Permohonan Bantuan'), findsOneWidget);
      expect(find.text(ForgotPasswordPage.requestTemplate), findsOneWidget);
      expect(find.text('Salin Template'), findsOneWidget);
      expect(find.text('Kembali ke Login'), findsOneWidget);
    });

    testWidgets('copy button puts template into clipboard and shows notification', (tester) async {
      tester.view.physicalSize = const Size(393, 873);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final log = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          log.add(methodCall);
          return null;
        },
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final copyButton = find.text('Salin Template');
      await tester.ensureVisible(copyButton);
      await tester.tap(copyButton);
      await tester.pumpAndSettle();

      expect(
        log.any(
          (call) =>
              call.method == 'Clipboard.setData' &&
              (call.arguments as Map)['text'] == ForgotPasswordPage.requestTemplate,
        ),
        isTrue,
      );

      expect(find.text('Tersalin'), findsOneWidget);
      expect(find.text('Template permohonan telah disalin ke clipboard.'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    for (final size in [
      const Size(360, 800),
      const Size(393, 873),
      const Size(412, 915),
    ]) {
      testWidgets('renders cleanly without overflow on size ${size.width}x${size.height}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Salin Template'), findsOneWidget);
      });
    }
  });
}
