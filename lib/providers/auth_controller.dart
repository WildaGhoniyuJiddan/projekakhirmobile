import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthbang/providers/providers.dart';
import 'package:worthbang/services/core/api_exception.dart';
import 'package:worthbang/models/auth_models.dart';
import 'package:worthbang/services/auth/auth_repository.dart';
import 'package:worthbang/services/auth/biometric_service.dart';

/// Status sesi auth aplikasi.
enum AuthStatus { unknown, authenticated, unauthenticated }

/// State auth: status + user aktif + pesan error terakhir.
class AuthState {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.error,
    this.isLoading = false,
  });

  final AuthStatus status;
  final AppUser? user;
  final String? error;
  final bool isLoading;

  AuthState copyWith({
    AuthStatus? status,
    AppUser? user,
    String? error,
    bool? isLoading,
  }) => AuthState(
    status: status ?? this.status,
    user: user ?? this.user,
    error: error,
    isLoading: isLoading ?? this.isLoading,
  );
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(storage: ref.watch(tokenStorageProvider));
});

final biometricServiceProvider = Provider<BiometricService>(
  (ref) => BiometricService(),
);

/// Controller sesi: login, register, restore, logout paksa.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    // Pulihkan sesi saat controller pertama dibuat.
    Future.microtask(_restore);
    // Logout paksa saat interceptor gagal refresh (401).
    ref.watch(apiClientProvider).onForceLogout.listen((_) => forceLogout());
    return const AuthState();
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<void> _restore() async {
    final storage = ref.read(tokenStorageProvider);
    final refreshToken = await storage.readRefreshToken();
    final biometricEnabled = await storage.isBiometricEnabled();
    final biometricAvailable = await ref
        .read(biometricServiceProvider)
        .isAvailable;
    if (refreshToken != null &&
        refreshToken.isNotEmpty &&
        biometricEnabled &&
        biometricAvailable) {
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return;
    }

    final user = await _repo.restoreSession();
    state = state.copyWith(
      status: user == null
          ? AuthStatus.unauthenticated
          : AuthStatus.authenticated,
      user: user,
    );
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final session = await _repo.login(email: email, password: password);
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: session.user,
        isLoading: false,
      );
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      return false;
    }
  }

  Future<bool> register(String name, String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final session = await _repo.register(
        name: name,
        email: email,
        password: password,
      );
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: session.user,
        isLoading: false,
      );
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      return false;
    }
  }

  /// Dipanggil setelah biometric lolos: pulihkan sesi tanpa password.
  Future<bool> unlockWithBiometric() async {
    final bio = ref.read(biometricServiceProvider);
    if (!await bio.authenticate()) return false;
    final user = await _repo.restoreSession();
    if (user == null) return false;
    state = state.copyWith(status: AuthStatus.authenticated, user: user);
    return true;
  }

  Future<void> logout() async {
    await _repo.logout();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// Refresh data user di state (mis. setelah update profil).
  void setUser(AppUser user) {
    state = state.copyWith(user: user);
  }

  /// Logout paksa dari interceptor (refresh token gagal).
  Future<void> forceLogout() async {
    await _repo.logout();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
