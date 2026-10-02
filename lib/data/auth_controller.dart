import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/enums.dart';
import '../models/rows.dart';
import 'api.dart';

/// Holds the signed-in user, their profile, and (for drivers) their driver and
/// vehicle records.
class AuthController extends ChangeNotifier {
  AuthController(this.api);

  final Api api;
  StreamSubscription<AuthState>? _sub;

  bool loading = true;
  Session? session;
  Profile? profile;
  Driver? driver;
  Vehicle? vehicle;
  String? error;

  UserRole? get role => profile?.role;
  String? get userId => session?.user.id;
  bool get isSignedIn => session != null;

  Future<void> init() async {
    session = api.currentSession;
    await _loadContext();
    loading = false;
    notifyListeners();

    _sub = api.authStateChanges.listen((state) async {
      session = state.session;
      await _loadContext();
      notifyListeners();
    });
  }

  Future<void> _loadContext() async {
    final id = session?.user.id;
    if (id == null) {
      profile = null;
      driver = null;
      vehicle = null;
      return;
    }
    profile = await api.fetchProfile(id);
    driver = await api.fetchDriver(id);
    vehicle = driver == null ? null : await api.fetchVehicle(driver!.id);
  }

  Future<void> refresh() async {
    await _loadContext();
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    error = null;
    try {
      await api.signIn(email, password);
      await refresh();
    } on AuthException catch (e) {
      error = e.message;
      rethrow;
    }
  }

  /// Returns true when the account was created but needs email confirmation.
  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    required UserRole role,
  }) async {
    error = null;
    try {
      final res = await api.signUp(
        email: email,
        password: password,
        fullName: fullName,
        phone: phone,
        role: role,
      );
      await refresh();
      return res.session == null;
    } on AuthException catch (e) {
      error = e.message;
      rethrow;
    }
  }

  Future<void> signOut() async {
    await api.signOut();
    profile = null;
    driver = null;
    vehicle = null;
    session = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
