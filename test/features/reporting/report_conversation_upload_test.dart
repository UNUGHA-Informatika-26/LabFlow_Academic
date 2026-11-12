import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:labflow/core/connectivity/connectivity_service.dart';
import 'package:labflow/features/asset/data/asset_image_service.dart';
import 'package:labflow/features/reporting/data/report_conversation_service.dart';
import 'package:labflow/features/reporting/presentation/cubit/report_conversation_cubit.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/fake_firestore.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}
class _MockUser extends Mock implements User {}
class _MockAssetImageService extends Mock implements AssetImageService {}
class _MockConnectivityService extends Mock implements ConnectivityService {}

void main() {
  setUpAll(() {
    registerFallbackValue(XFile('dummy.png'));
  });

  late FakeMemoryFirestore fakeFirestore;
  late _MockFirebaseAuth mockAuth;
  late _MockUser mockUser;
  late _MockAssetImageService mockImages;
  late _MockConnectivityService mockConnectivity;

  setUp(() {
    fakeFirestore = FakeMemoryFirestore();
    mockAuth = _MockFirebaseAuth();
    mockUser = _MockUser();
    mockImages = _MockAssetImageService();
    mockConnectivity = _MockConnectivityService();

    when(() => mockUser.uid).thenReturn('student-123');
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockConnectivity.hasNetworkInterface()).thenAnswer((_) async => true);

    fakeFirestore.seedDoc('users', 'student-123', {
      'role': 'student',
      'status': 'active',
      'fullName': 'Ahmad Dahlan',
    });
  });

  group('ReportConversationService Image Upload', () {
    test('successfully uploads image and writes imageUrl to messages', () async {
      when(
        () => mockImages.uploadImage(
          image: any(named: 'image'),
          folder: 'labflow/reports/rep-1/chat',
          maximumBytes: 5 * 1024 * 1024,
        ),
      ).thenAnswer(
        (_) async => const CloudinaryImageUpload(
          secureUrl: 'https://res.cloudinary.com/demo/image/upload/sample.jpg',
          publicId: 'labflow/reports/rep-1/chat/sample',
        ),
      );

      final service = ReportConversationService(
        firestore: fakeFirestore,
        auth: mockAuth,
        images: mockImages,
        connectivity: mockConnectivity,
      );

      await service.send(
        'rep-1',
        'Kabel power terbakar',
        image: XFile('test/fixtures/cable.jpg'),
      );

      final messages = fakeFirestore.writesFor('reports/rep-1/messages');
      expect(messages, isNotEmpty);
      final lastWrite = messages.last;
      expect(lastWrite.payload['type'], 'mixed');
      expect(
        lastWrite.payload['imageUrl'],
        'https://res.cloudinary.com/demo/image/upload/sample.jpg',
      );
      expect(
        lastWrite.payload['imagePublicId'],
        'labflow/reports/rep-1/chat/sample',
      );
      expect(lastWrite.payload['senderId'], 'student-123');
    });

    test('sets message type to image when text is empty', () async {
      when(
        () => mockImages.uploadImage(
          image: any(named: 'image'),
          folder: 'labflow/reports/rep-1/chat',
          maximumBytes: 5 * 1024 * 1024,
        ),
      ).thenAnswer(
        (_) async => const CloudinaryImageUpload(
          secureUrl: 'https://res.cloudinary.com/demo/image/upload/photo.png',
          publicId: 'photo-1',
        ),
      );

      final service = ReportConversationService(
        firestore: fakeFirestore,
        auth: mockAuth,
        images: mockImages,
        connectivity: mockConnectivity,
      );

      await service.send(
        'rep-1',
        '',
        image: XFile('test/fixtures/photo.png'),
      );

      final messages = fakeFirestore.writesFor('reports/rep-1/messages');
      final lastWrite = messages.last;
      expect(lastWrite.payload['type'], 'image');
      expect(lastWrite.payload['imageUrl'], isNotNull);
      expect(lastWrite.payload['text'], '');
    });

    test('fails and prevents write when network is unavailable for image upload', () async {
      when(() => mockConnectivity.hasNetworkInterface()).thenAnswer((_) async => false);

      final service = ReportConversationService(
        firestore: fakeFirestore,
        auth: mockAuth,
        images: mockImages,
        connectivity: mockConnectivity,
      );

      expect(
        () => service.send(
          'rep-1',
          'Pesan penting',
          image: XFile('test/fixtures/photo.png'),
        ),
        throwsA(isA<ReportConversationException>().having(
          (e) => e.message,
          'message',
          contains('Upload gambar membutuhkan koneksi internet'),
        )),
      );

      expect(fakeFirestore.writesFor('reports'), isEmpty);
    });

    test('rethrows AssetImageException as ReportConversationException without corrupting state', () async {
      when(
        () => mockImages.uploadImage(
          image: any(named: 'image'),
          folder: any(named: 'folder'),
          maximumBytes: any(named: 'maximumBytes'),
        ),
      ).thenThrow(const AssetImageException('Ukuran gambar maksimal 5 MB.'));

      final service = ReportConversationService(
        firestore: fakeFirestore,
        auth: mockAuth,
        images: mockImages,
        connectivity: mockConnectivity,
      );

      expect(
        () => service.send(
          'rep-1',
          'Pesan dengan foto terlalu besar',
          image: XFile('test/fixtures/large.jpg'),
        ),
        throwsA(isA<ReportConversationException>().having(
          (e) => e.message,
          'message',
          'Ukuran gambar maksimal 5 MB.',
        )),
      );

      expect(fakeFirestore.writesFor('reports'), isEmpty);
    });
  });

  group('ReportConversationCubit Error Retention', () {
    test('emits error and stops sending when service throws', () async {
      when(
        () => mockImages.uploadImage(
          image: any(named: 'image'),
          folder: any(named: 'folder'),
          maximumBytes: any(named: 'maximumBytes'),
        ),
      ).thenThrow(const AssetImageException('Konfigurasi upload belum tersedia.'));

      final service = ReportConversationService(
        firestore: fakeFirestore,
        auth: mockAuth,
        images: mockImages,
        connectivity: mockConnectivity,
      );

      final cubit = ReportConversationCubit(service, auth: mockAuth);
      cubit.watch('rep-1');

      await cubit.send('Catatan penting', image: XFile('test/fixtures/shot.jpg'));

      expect(cubit.state.sending, isFalse);
      expect(cubit.state.errorMessage, 'Konfigurasi upload belum tersedia.');
    });
  });

  group('AssetImageService Default Fallback', () {
    test('has effective defaults configured for academic environment', () {
      final imageService = AssetImageService();
      expect(imageService.effectiveCloudName, isNotEmpty);
      expect(imageService.effectiveUploadPreset, isNotEmpty);
    });
  });
}
