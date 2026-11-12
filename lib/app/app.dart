import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/connectivity/connectivity_cubit.dart';
import '../core/connectivity/connectivity_service.dart';
import '../core/connectivity/connectivity_state.dart';
import '../core/connectivity/offline_banner.dart';
import '../features/auth/data/auth_service.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

class LabFlowApp extends StatefulWidget {
  const LabFlowApp({required this.initialLocation, super.key});

  final String initialLocation;

  @override
  State<LabFlowApp> createState() => _LabFlowAppState();
}

class _LabFlowAppState extends State<LabFlowApp> with WidgetsBindingObserver {
  late final GoRouter _router;
  late final AuthService _authService = AuthService();
  Timer? _expiryTimer;
  bool _checkingSession = false;
  bool _verifyProfilePending = false;
  late final ConnectivityCubit _connectivityCubit;
  StreamSubscription<ConnectivityState>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _connectivityCubit = ConnectivityCubit(PluginConnectivityService());
    _connectivitySubscription = _connectivityCubit.stream.listen((state) {
      if (state.status == ConnectivityStatus.networkAvailable &&
          _isProtectedRoute) {
        unawaited(_checkSession(verifyProfile: true));
      }
    });
    unawaited(_connectivityCubit.start());
    _router = createAppRouter(initialLocation: widget.initialLocation);
    _router.routeInformationProvider.addListener(_onRouteChanged);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onRouteChanged());
  }

  bool get _isProtectedRoute {
    final path = _router.routeInformationProvider.value.uri.path;
    return path == '/student' ||
        path.startsWith('/student/') ||
        path == '/lab-admin' ||
        path.startsWith('/lab-admin/') ||
        path == '/superadmin' ||
        path.startsWith('/superadmin/');
  }

  bool _matchesRolePrefix(String path, String role) => switch (role) {
    'student' => path == '/student' || path.startsWith('/student/'),
    'lab_admin' => path == '/lab-admin' || path.startsWith('/lab-admin/'),
    'superadmin' => path == '/superadmin' || path.startsWith('/superadmin/'),
    _ => false,
  };

  String _homePathForRole(String role) => switch (role) {
    'student' => '/student',
    'lab_admin' => '/lab-admin',
    'superadmin' => '/superadmin',
    _ => '/login',
  };

  void _onRouteChanged() {
    _expiryTimer?.cancel();
    if (_isProtectedRoute) unawaited(_checkSession());
  }

  Future<void> _checkSession({bool verifyProfile = false}) async {
    if (!mounted || !_isProtectedRoute) return;
    if (_checkingSession) {
      _verifyProfilePending |= verifyProfile;
      return;
    }
    _checkingSession = true;
    try {
      final session = await _authService.requireValidSession();
      if (!mounted || !_isProtectedRoute) return;
      if (verifyProfile) {
        final profile = await _authService.getCurrentUserProfile(
          forceRefresh: true,
        );
        if (!mounted || !_isProtectedRoute) return;
        final currentPath = _router.routeInformationProvider.value.uri.path;
        if (!_matchesRolePrefix(currentPath, profile.role)) {
          _router.go(_homePathForRole(profile.role));
          return;
        }
      }
      final remaining = session.expiresAt.difference(DateTime.now().toUtc());
      _expiryTimer?.cancel();
      _expiryTimer = Timer(
        remaining.isNegative ? Duration.zero : remaining,
        () => unawaited(_checkSession()),
      );
    } catch (_) {
      if (mounted && _isProtectedRoute) _router.go('/login');
    } finally {
      _checkingSession = false;
      if (_verifyProfilePending && mounted && _isProtectedRoute) {
        _verifyProfilePending = false;
        unawaited(_checkSession(verifyProfile: true));
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkSession(verifyProfile: true));
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _router.routeInformationProvider.removeListener(_onRouteChanged);
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    unawaited(_connectivitySubscription?.cancel());
    _connectivityCubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _connectivityCubit,
      child: MaterialApp.router(
        title: 'LabFlow',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: _router,
        builder: (context, child) =>
            OfflineBanner(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
