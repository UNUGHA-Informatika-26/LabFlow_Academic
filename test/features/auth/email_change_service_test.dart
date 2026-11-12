// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:labflow/features/auth/data/email_change_service.dart';
import 'package:labflow/features/auth/domain/email_change_request.dart';
import 'package:mocktail/mocktail.dart';

class _FirebaseAuthMock extends Mock implements FirebaseAuth {}
class _UserMock extends Mock implements User {}
class _FirebaseFirestoreMock extends Mock implements FirebaseFirestore {}
class _CollectionReferenceMock extends Mock
    implements CollectionReference<Map<String, dynamic>> {}
class _DocumentReferenceMock extends Mock
    implements DocumentReference<Map<String, dynamic>> {}
class _QueryMock extends Mock
    implements Query<Map<String, dynamic>> {}
class _QuerySnapshotMock extends Mock
    implements QuerySnapshot<Map<String, dynamic>> {}
class _QueryDocumentSnapshotMock extends Mock
    implements QueryDocumentSnapshot<Map<String, dynamic>> {}

void main() {
  late _FirebaseFirestoreMock mockFirestore;
  late _CollectionReferenceMock mockCollection;
  late _DocumentReferenceMock mockDocRef;
  late _FirebaseAuthMock mockAuth;
  late _UserMock mockUser;
  late EmailChangeService service;

  setUp(() {
    mockFirestore = _FirebaseFirestoreMock();
    mockCollection = _CollectionReferenceMock();
    mockDocRef = _DocumentReferenceMock();
    mockAuth = _FirebaseAuthMock();
    mockUser = _UserMock();

    when(() => mockFirestore.collection('email_change_requests'))
        .thenReturn(mockCollection);
    when(() => mockCollection.doc(any())).thenReturn(mockDocRef);
    when(() => mockCollection.doc()).thenReturn(mockDocRef);
    when(() => mockDocRef.id).thenReturn('test-req-id');

    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.uid).thenReturn('student-1');
    when(() => mockUser.email).thenReturn('old@labflow.test');

    service = EmailChangeService(
      firestore: mockFirestore,
      auth: mockAuth,
    );
  });

  group('EmailChangeService Unit Tests', () {
    test('submits valid email change request with pending status', () async {
      final mockQuery1 = _QueryMock();
      final mockQuery2 = _QueryMock();
      final mockEmptySnapshot = _QuerySnapshotMock();

      when(() => mockCollection.where('uid', isEqualTo: 'student-1'))
          .thenReturn(mockQuery1);
      when(() => mockQuery1.where('status', isEqualTo: 'pending'))
          .thenReturn(mockQuery2);
      when(() => mockQuery2.get())
          .thenAnswer((_) async => mockEmptySnapshot);
      when(() => mockEmptySnapshot.docs).thenReturn([]);
      when(() => mockDocRef.set(any())).thenAnswer((_) async {});

      final reqId = await service.submitRequest(
        newEmail: 'new@labflow.test',
        reason: 'Alamat email lama sudah tidak aktif',
      );

      expect(reqId, 'test-req-id');
      verify(() => mockDocRef.set(any(that: isA<Map<String, dynamic>>().having(
        (m) => m['status'],
        'status',
        'pending',
      )))).called(1);
    });

    test('rejects submission when new email is identical to current email', () async {
      expect(
        () => service.submitRequest(
          newEmail: 'old@labflow.test',
          reason: 'Tidak ada perubahan',
        ),
        throwsA(isA<EmailChangeException>().having(
          (e) => e.message,
          'message',
          contains('harus berbeda'),
        )),
      );
    });

    test('rejects submission when short reason or invalid email format', () async {
      expect(
        () => service.submitRequest(
          newEmail: 'invalid-email',
          reason: 'Alasan valid panjang',
        ),
        throwsA(isA<EmailChangeException>()),
      );

      expect(
        () => service.submitRequest(
          newEmail: 'valid@labflow.test',
          reason: '123',
        ),
        throwsA(isA<EmailChangeException>().having(
          (e) => e.message,
          'message',
          contains('minimal 5 karakter'),
        )),
      );
    });

    test('rejects submission when pending request already exists for user', () async {
      final mockQuery1 = _QueryMock();
      final mockQuery2 = _QueryMock();
      final mockNonEmptySnapshot = _QuerySnapshotMock();
      final mockDocSnapshot = _QueryDocumentSnapshotMock();

      when(() => mockCollection.where('uid', isEqualTo: 'student-1'))
          .thenReturn(mockQuery1);
      when(() => mockQuery1.where('status', isEqualTo: 'pending'))
          .thenReturn(mockQuery2);
      when(() => mockQuery2.get())
          .thenAnswer((_) async => mockNonEmptySnapshot);
      when(() => mockNonEmptySnapshot.docs).thenReturn([mockDocSnapshot]);

      expect(
        () => service.submitRequest(
          newEmail: 'second@labflow.test',
          reason: 'Mencoba request kedua',
        ),
        throwsA(isA<EmailChangeException>().having(
          (e) => e.message,
          'message',
          contains('menunggu persetujuan'),
        )),
      );
    });

    test('sendVerificationLink calls verifyBeforeUpdateEmail only when approved', () async {
      when(() => mockUser.verifyBeforeUpdateEmail(any())).thenAnswer((_) async {});

      final pendingReq = EmailChangeRequest(
        id: 'req-pending',
        uid: 'student-1',
        currentEmail: 'old@labflow.test',
        requestedEmail: 'new@labflow.test',
        reason: 'Alasan',
        status: 'pending',
        requestedAt: DateTime.now(),
      );

      expect(
        () => service.sendVerificationLink(pendingReq),
        throwsA(isA<EmailChangeException>().having(
          (e) => e.message,
          'message',
          contains('disetujui Superadmin'),
        )),
      );

      final approvedReq = EmailChangeRequest(
        id: 'req-approved',
        uid: 'student-1',
        currentEmail: 'old@labflow.test',
        requestedEmail: 'new@labflow.test',
        reason: 'Alasan',
        status: 'approved',
        requestedAt: DateTime.now(),
      );

      await service.sendVerificationLink(approvedReq);
      verify(() => mockUser.verifyBeforeUpdateEmail('new@labflow.test')).called(1);
    });

    test('checkAndSyncVerifiedEmail reloads user, forces ID token refresh (true) before Firestore updates, and syncs profile', () async {
      final mockReloadedUser = _UserMock();
      final mockUsersCollection = _CollectionReferenceMock();
      final mockUserDocRef = _DocumentReferenceMock();

      var reloadCompleted = false;
      when(() => mockAuth.currentUser)
          .thenAnswer((_) => reloadCompleted ? mockReloadedUser : mockUser);
      when(() => mockUser.reload()).thenAnswer((_) async {
        reloadCompleted = true;
      });

      when(() => mockReloadedUser.uid).thenReturn('student-1');
      when(() => mockReloadedUser.email).thenReturn('new@labflow.test');
      when(() => mockReloadedUser.emailVerified).thenReturn(true);
      when(() => mockReloadedUser.getIdToken(true))
          .thenAnswer((_) async => 'refreshed-id-token');

      when(() => mockFirestore.collection('users')).thenReturn(mockUsersCollection);
      when(() => mockUsersCollection.doc('student-1')).thenReturn(mockUserDocRef);
      when(() => mockDocRef.update(any())).thenAnswer((_) async {});
      when(() => mockUserDocRef.update(any())).thenAnswer((_) async {});

      final approvedReq = EmailChangeRequest(
        id: 'req-sync',
        uid: 'student-1',
        currentEmail: 'old@labflow.test',
        requestedEmail: 'new@labflow.test',
        reason: 'Alasan',
        status: 'approved',
        requestedAt: DateTime.now(),
      );

      final synced = await service.checkAndSyncVerifiedEmail(approvedReq);
      expect(synced, isTrue);

      verifyInOrder([
        () => mockUser.reload(),
        () => mockReloadedUser.getIdToken(true),
        () => mockUserDocRef.update(any()),
        () => mockDocRef.update(any()),
      ]);
      verifyNever(() => mockUser.getIdToken(any()));
    });

    test('checkAndSyncVerifiedEmail returns false and skips token refresh/Firestore update when email is unverified', () async {
      when(() => mockUser.reload()).thenAnswer((_) async {});
      when(() => mockUser.email).thenReturn('old@labflow.test');
      when(() => mockUser.emailVerified).thenReturn(false);

      final approvedReq = EmailChangeRequest(
        id: 'req-unverified',
        uid: 'student-1',
        currentEmail: 'old@labflow.test',
        requestedEmail: 'new@labflow.test',
        reason: 'Alasan',
        status: 'approved',
        requestedAt: DateTime.now(),
      );

      final synced = await service.checkAndSyncVerifiedEmail(approvedReq);
      expect(synced, isFalse);

      verify(() => mockUser.reload()).called(1);
      verifyNever(() => mockUser.getIdToken(any()));
      verifyNever(() => mockFirestore.collection('users'));
      verifyNever(() => mockDocRef.update(any()));
    });

    test('checkAndSyncVerifiedEmail throws and aborts when currentUser becomes null after reload', () async {
      var reloadCompleted = false;
      when(() => mockAuth.currentUser)
          .thenAnswer((_) => reloadCompleted ? null : mockUser);
      when(() => mockUser.reload()).thenAnswer((_) async {
        reloadCompleted = true;
      });

      final approvedReq = EmailChangeRequest(
        id: 'req-null-user',
        uid: 'student-1',
        currentEmail: 'old@labflow.test',
        requestedEmail: 'new@labflow.test',
        reason: 'Alasan',
        status: 'approved',
        requestedAt: DateTime.now(),
      );

      await expectLater(
        service.checkAndSyncVerifiedEmail(approvedReq),
        throwsA(isA<EmailChangeException>().having(
          (e) => e.message,
          'message',
          contains('memuat ulang sesi'),
        )),
      );

      verifyNever(() => mockUser.getIdToken(any()));
      verifyNever(() => mockFirestore.collection('users'));
      verifyNever(() => mockDocRef.update(any()));
    });

    test('checkAndSyncVerifiedEmail throws and aborts when UID changes after reload', () async {
      final mockOtherUser = _UserMock();
      var reloadCompleted = false;
      when(() => mockAuth.currentUser)
          .thenAnswer((_) => reloadCompleted ? mockOtherUser : mockUser);
      when(() => mockUser.reload()).thenAnswer((_) async {
        reloadCompleted = true;
      });
      when(() => mockOtherUser.uid).thenReturn('other-user-uid');

      final approvedReq = EmailChangeRequest(
        id: 'req-uid-changed',
        uid: 'student-1',
        currentEmail: 'old@labflow.test',
        requestedEmail: 'new@labflow.test',
        reason: 'Alasan',
        status: 'approved',
        requestedAt: DateTime.now(),
      );

      await expectLater(
        service.checkAndSyncVerifiedEmail(approvedReq),
        throwsA(isA<EmailChangeException>().having(
          (e) => e.message,
          'message',
          contains('Identitas pengguna berubah'),
        )),
      );

      verifyNever(() => mockOtherUser.getIdToken(any()));
      verifyNever(() => mockFirestore.collection('users'));
      verifyNever(() => mockDocRef.update(any()));
    });

    test('checkAndSyncVerifiedEmail does not update Firestore when ID token refresh fails or returns empty', () async {
      final mockUsersCollection = _CollectionReferenceMock();
      final mockUserDocRef = _DocumentReferenceMock();
      when(() => mockFirestore.collection('users')).thenReturn(mockUsersCollection);
      when(() => mockUsersCollection.doc('student-1')).thenReturn(mockUserDocRef);

      when(() => mockUser.reload()).thenAnswer((_) async {});
      when(() => mockUser.email).thenReturn('new@labflow.test');
      when(() => mockUser.emailVerified).thenReturn(true);

      final approvedReq = EmailChangeRequest(
        id: 'req-token-fail',
        uid: 'student-1',
        currentEmail: 'old@labflow.test',
        requestedEmail: 'new@labflow.test',
        reason: 'Alasan',
        status: 'approved',
        requestedAt: DateTime.now(),
      );

      // Case A: getIdToken(true) throws FirebaseAuthException
      when(() => mockUser.getIdToken(true)).thenThrow(
        FirebaseAuthException(code: 'network-request-failed', message: 'Offline'),
      );

      await expectLater(
        service.checkAndSyncVerifiedEmail(approvedReq),
        throwsA(isA<EmailChangeException>().having(
          (e) => e.code,
          'code',
          'network-request-failed',
        )),
      );

      verify(() => mockUser.getIdToken(true)).called(1);
      verifyNever(() => mockUserDocRef.update(any()));
      verifyNever(() => mockDocRef.update(any()));

      // Case B: getIdToken(true) returns null/empty token
      when(() => mockUser.getIdToken(true)).thenAnswer((_) async => '');

      await expectLater(
        service.checkAndSyncVerifiedEmail(approvedReq),
        throwsA(isA<EmailChangeException>()),
      );

      verify(() => mockUser.getIdToken(true)).called(1);
      verifyNever(() => mockUserDocRef.update(any()));
      verifyNever(() => mockDocRef.update(any()));
    });
  });
}
