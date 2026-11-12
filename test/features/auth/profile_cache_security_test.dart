import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:labflow/core/session/app_session_manager.dart';
import 'package:labflow/features/auth/data/auth_service.dart';
import 'package:labflow/features/lab_admin/data/lab_admin_profile_service.dart';
import 'package:labflow/features/student/data/student_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../helpers/fake_firestore.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _MockUserCredential extends Mock implements UserCredential {}

class _MemorySessionStorage implements AppSessionStorage {
  AppSession? session;

  @override
  Future<AppSession?> read() async => session;

  @override
  Future<void> write(AppSession value) async => session = value;

  @override
  Future<void> clear() async => session = null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime currentClock;
  late FakeMemoryFirestore firestore;
  late _MockFirebaseAuth firebaseAuth;
  late _MockUser userA;
  late _MockUser userB;
  late _MemorySessionStorage sessionStorage;
  late AppSessionManager sessionManager;
  late AuthService authService;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    currentClock = DateTime.utc(2026, 11, 1, 9, 0, 0);
    firestore = FakeMemoryFirestore(clock: () => currentClock);
    firebaseAuth = _MockFirebaseAuth();
    userA = _MockUser();
    userB = _MockUser();

    when(() => userA.uid).thenReturn('user-a');
    when(() => userA.email).thenReturn('usera@labflow.test');
    when(() => userB.uid).thenReturn('user-b');
    when(() => userB.email).thenReturn('userb@labflow.test');
    when(() => firebaseAuth.signOut()).thenAnswer((_) async {});

    sessionStorage = _MemorySessionStorage();
    sessionManager = AppSessionManager(
      storage: sessionStorage,
      now: () => currentClock,
    );

    AuthService.clearProfileCache();

    firestore.seedDoc('users', 'user-a', {
      'uid': 'user-a',
      'email': 'usera@labflow.test',
      'fullName': 'User A Student',
      'role': 'student',
      'status': 'active',
      'nim': '11111',
    });

    firestore.seedDoc('users', 'user-b', {
      'uid': 'user-b',
      'email': 'userb@labflow.test',
      'fullName': 'User B Lab Admin',
      'role': 'lab_admin',
      'status': 'active',
      'nip': '22222',
    });

    authService = AuthService(
      firebaseAuth: firebaseAuth,
      firestore: firestore,
      sessionManager: sessionManager,
    );
  });

  group('Task E — Profile Cache Security & Invalidation', () {
    test('1. Logout completely clears profile cache even if currentUser is already null', () async {
      when(() => firebaseAuth.currentUser).thenReturn(userA);
      await sessionManager.start('user-a');

      final profile = await authService.getCurrentUserProfile();
      expect(profile.uid, 'user-a');
      expect(AuthService.debugCachedProfile('user-a'), isNotNull);

      // Simulate FirebaseAuth currentUser already becoming null before signOut completes:
      when(() => firebaseAuth.currentUser).thenReturn(null);
      await authService.signOut();

      expect(AuthService.debugCachedProfile('user-a'), isNull);
      expect(sessionStorage.session, isNull);
    });

    test('2. Account switching (User A -> User B) never leaks or mixes User A cache', () async {
      final credA = _MockUserCredential();
      final credB = _MockUserCredential();

      when(() => firebaseAuth.currentUser).thenReturn(userA);
      when(
        () => firebaseAuth.signInWithEmailAndPassword(
          email: 'usera@labflow.test',
          password: 'Password123!',
        ),
      ).thenAnswer((_) async => credA);

      final signedInA = await authService.signIn(
        email: 'usera@labflow.test',
        password: 'Password123!',
      );
      expect(signedInA.uid, 'user-a');
      expect(AuthService.debugCachedProfile('user-a')?.fullName, 'User A Student');

      // Switch directly to User B:
      when(() => firebaseAuth.currentUser).thenReturn(userB);
      when(
        () => firebaseAuth.signInWithEmailAndPassword(
          email: 'userb@labflow.test',
          password: 'Password123!',
        ),
      ).thenAnswer((_) async => credB);

      final signedInB = await authService.signIn(
        email: 'userb@labflow.test',
        password: 'Password123!',
      );
      expect(signedInB.uid, 'user-b');
      expect(signedInB.role, 'lab_admin');
      // User A's cached profile must be evicted!
      expect(AuthService.debugCachedProfile('user-a'), isNull);
      expect(
        AuthService.debugCachedProfile('user-b')?.fullName,
        'User B Lab Admin',
      );
    });

    test('3. Role changes on server invalidate stale role on forceRefresh and service check', () async {
      when(() => firebaseAuth.currentUser).thenReturn(userB);
      await sessionManager.start('user-b');

      final initialProfile = await authService.getCurrentUserProfile();
      expect(initialProfile.role, 'lab_admin');

      // Superadmin changes User B's role from 'lab_admin' to 'student' on the server:
      firestore.seedDoc('users', 'user-b', {
        ...firestore.peekDoc('users', 'user-b')!,
        'role': 'student',
      });

      // LabAdminProfileService rejects stale Lab Admin access and evicts cache:
      final labAdminProfileService = LabAdminProfileService(
        firestore: firestore,
        firebaseAuth: firebaseAuth,
      );
      await expectLater(
        labAdminProfileService.loadProfile,
        throwsA(isA<LabAdminProfileException>()),
      );
      expect(AuthService.debugCachedProfile('user-b'), isNull);

      // Refreshing profile via AuthService loads the new 'student' role:
      final refreshed = await authService.getCurrentUserProfile(
        forceRefresh: true,
      );
      expect(refreshed.role, 'student');
      expect(AuthService.debugCachedProfile('user-b')?.role, 'student');
    });

    test('4. Account becoming inactive (suspended) clears cache, signs out, and denies access', () async {
      when(() => firebaseAuth.currentUser).thenReturn(userA);
      await sessionManager.start('user-a');

      await authService.getCurrentUserProfile();
      expect(AuthService.debugCachedProfile('user-a'), isNotNull);

      // Account is suspended on the server:
      firestore.seedDoc('users', 'user-a', {
        ...firestore.peekDoc('users', 'user-a')!,
        'status': 'suspended',
      });

      // Authoritative refresh (e.g. on reconnect or app resume) immediately rejects, clears cache, and signs out:
      await expectLater(
        () => authService.getCurrentUserProfile(forceRefresh: true),
        throwsA(
          isA<AuthServiceException>().having(
            (e) => e.isAccountSuspended,
            'isAccountSuspended',
            isTrue,
          ),
        ),
      );
      expect(AuthService.debugCachedProfile('user-a'), isNull);
      expect(sessionStorage.session, isNull);

      // Direct StudentService.loadProfile also enforces active status:
      await sessionManager.start('user-a');
      final studentService = StudentService(
        firestore: firestore,
        firebaseAuth: firebaseAuth,
      );
      await expectLater(
        studentService.loadProfile,
        throwsA(isA<StudentServiceException>()),
      );
    });

    test('5 & 6. Cache serves valid session when offline and updates on reconnect forceRefresh', () async {
      when(() => firebaseAuth.currentUser).thenReturn(userA);
      await sessionManager.start('user-a');

      final first = await authService.getCurrentUserProfile();
      expect(first.fullName, 'User A Student');

      // Update server data while client reads from cache (forceRefresh: false):
      firestore.seedDoc('users', 'user-a', {
        ...firestore.peekDoc('users', 'user-a')!,
        'fullName': 'User A Updated Server',
      });

      final fromCache = await authService.getCurrentUserProfile();
      expect(fromCache.fullName, 'User A Student');

      // When network reconnects or app resumes, forceRefresh: true updates cache from server:
      final afterReconnect = await authService.getCurrentUserProfile(
        forceRefresh: true,
      );
      expect(afterReconnect.fullName, 'User A Updated Server');
      expect(
        AuthService.debugCachedProfile('user-a')?.fullName,
        'User A Updated Server',
      );
    });

    test('7. Race condition: in-flight profile load during logout cannot repopulate cleared cache', () async {
      when(() => firebaseAuth.currentUser).thenReturn(userA);
      await sessionManager.start('user-a');

      final getCompleter = Completer<void>();
      final gateEntered = Completer<void>();
      firestore.onBeforeDocGet = (collection, docId) async {
        if (collection == 'users' && docId == 'user-a') {
          if (!gateEntered.isCompleted) gateEntered.complete();
          await getCompleter.future;
        }
      };

      // Start an in-flight profile load for User A:
      final inFlightFuture = authService.getCurrentUserProfile(
        forceRefresh: true,
      );
      await gateEntered.future;

      // User logs out while the Firestore read is still in-flight:
      when(() => firebaseAuth.currentUser).thenReturn(null);
      await authService.signOut();
      expect(AuthService.debugCachedProfile('user-a'), isNull);

      // Now allow the stale Firestore read for User A to finish:
      getCompleter.complete();

      await expectLater(
        inFlightFuture,
        throwsA(isA<AuthServiceException>()),
      );

      // Cache must remain completely empty and never repopulated by the stale response:
      expect(AuthService.debugCachedProfile('user-a'), isNull);
    });

    test('8. Race condition: in-flight profile load for User A during switch to User B cannot overwrite User B session or cache', () async {
      when(() => firebaseAuth.currentUser).thenReturn(userA);
      await sessionManager.start('user-a');

      final userAGetCompleter = Completer<void>();
      final userAGateEntered = Completer<void>();
      firestore.onBeforeDocGet = (collection, docId) async {
        if (collection == 'users' && docId == 'user-a') {
          if (!userAGateEntered.isCompleted) userAGateEntered.complete();
          await userAGetCompleter.future;
        }
      };

      // Start slow profile refresh for User A:
      final staleUserAFuture = authService.getCurrentUserProfile(
        forceRefresh: true,
      );
      await userAGateEntered.future;

      // While User A's request is in flight, account switches to User B:
      final credB = _MockUserCredential();
      when(() => firebaseAuth.currentUser).thenReturn(userB);
      when(
        () => firebaseAuth.signInWithEmailAndPassword(
          email: 'userb@labflow.test',
          password: 'Password123!',
        ),
      ).thenAnswer((_) async => credB);

      final signedInB = await authService.signIn(
        email: 'userb@labflow.test',
        password: 'Password123!',
      );
      expect(signedInB.uid, 'user-b');
      expect(AuthService.debugCachedProfile('user-b')?.uid, 'user-b');

      // Now User A's slow Firestore read resolves:
      userAGetCompleter.complete();
      await expectLater(
        staleUserAFuture,
        throwsA(isA<AuthServiceException>()),
      );

      // User B's cache and session must be untouched, and User A must not be cached:
      expect(AuthService.debugCachedProfile('user-a'), isNull);
      expect(
        AuthService.debugCachedProfile('user-b')?.fullName,
        'User B Lab Admin',
      );
      expect(sessionStorage.session?.uid, 'user-b');
    });
  });
}
