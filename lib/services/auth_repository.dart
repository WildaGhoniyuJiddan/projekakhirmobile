import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:worthbang/models/auth_models.dart';
import 'package:worthbang/services/api_exception.dart';
import 'package:worthbang/services/token_storage.dart';

/// Repository auth di atas Supabase Auth.
///
/// Sesi (access/refresh token + auto-refresh) dikelola SDK Supabase.
/// [TokenStorage] hanya menyimpan CERMIN token & profil: dipakai
/// gerbang biometrik di AuthController dan cache [currentUser].
/// Fallback akun lokal & endpoint `/api/v1/auth/*` lama sudah dibuang.
class AuthRepository {
  AuthRepository({required TokenStorage storage, SupabaseClient? client})
      // ignore: prefer_initializing_formals — param publik, field privat.
      : _storage = storage,
        _injectedClient = client;

  final TokenStorage _storage;
  final SupabaseClient? _injectedClient;

  /// Client diambil malas agar provider tetap bisa dibuat sebelum
  /// `initSupabase()` jalan (config placeholder → error di pemakaian,
  /// bukan saat konstruksi).
  SupabaseClient get _supabase => _injectedClient ?? Supabase.instance.client;

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final session = res.session;
      final user = res.user;
      if (session == null || user == null) {
        throw const ApiException('Login gagal. Coba lagi.');
      }
      final appUser = await _resolveUser(user);
      return await _mirrorSession(session, appUser);
    } on AuthException catch (e) {
      throw ApiException(_authMessage(e), int.tryParse(e.statusCode ?? ''));
    }
  }

  Future<AuthSession> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final trimmedName = name.trim();
    try {
      final res = await _supabase.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'name': trimmedName},
      );
      final user = res.user;
      if (user == null) {
        throw const ApiException('Pendaftaran gagal. Coba lagi.');
      }
      final session = res.session;
      if (session == null) {
        // Proyek Supabase mewajibkan konfirmasi email: belum ada sesi
        // sampai user klik tautan verifikasi.
        throw const ApiException(
          'Pendaftaran berhasil. Cek email untuk verifikasi akun, lalu login.',
        );
      }
      await _upsertProfile(user.id, trimmedName);
      final appUser = AppUser(
        id: user.id,
        name: trimmedName,
        email: user.email ?? email.trim(),
      );
      return await _mirrorSession(session, appUser);
    } on AuthException catch (e) {
      throw ApiException(_authMessage(e), int.tryParse(e.statusCode ?? ''));
    }
  }

  /// Pulihkan sesi: dari sesi Supabase yang persisten, atau dari
  /// refresh token cermin di [TokenStorage]. Null bila tak ada sesi.
  Future<AppUser?> restoreSession() async {
    var session = _supabase.auth.currentSession;
    if (session == null) {
      final refreshToken = await _storage.readRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) return null;
      try {
        final res = await _supabase.auth.setSession(refreshToken);
        session = res.session;
      } catch (_) {
        await _storage.clear();
        return null;
      }
    }
    final user = _supabase.auth.currentUser;
    if (session == null || user == null) return null;
    final appUser = await _resolveUser(user);
    await _mirrorSession(session, appUser);
    return appUser;
  }

  Future<void> logout() async {
    try {
      await _supabase.auth.signOut();
    } catch (_) {
      // Logout lokal tetap jalan walau server unreachable.
    }
    await _storage.clear();
  }

  Future<AppUser?> currentUser() => _storage.readUser();

  Future<void> updateCachedUser(AppUser user) => _storage.saveUser(user);

  /// Bangun [AppUser] dari user Supabase: nama/foto dari tabel
  /// `profiles`, fallback metadata signup, lalu cache lokal.
  Future<AppUser> _resolveUser(User user) async {
    String? name;
    String? photoUrl;
    try {
      final row = await _supabase
          .from('profiles')
          .select('name, photo_url')
          .eq('id', user.id)
          .maybeSingle();
      name = row?['name'] as String?;
      photoUrl = row?['photo_url'] as String?;
    } catch (_) {
      // Tabel profiles belum ada / offline — lanjut ke fallback.
    }
    if (name == null || name.isEmpty) {
      name = user.userMetadata?['name'] as String?;
    }
    if (name == null || name.isEmpty) {
      final cached = await _storage.readUser();
      if (cached != null && cached.id == user.id) name = cached.name;
    }
    final email = user.email ?? '';
    return AppUser(
      id: user.id,
      name: (name == null || name.isEmpty) ? email.split('@').first : name,
      email: email,
      photoUrl: photoUrl,
    );
  }

  /// Insert baris `profiles` saat register (RLS: hanya baris sendiri).
  /// Best effort — nama juga tersimpan di metadata user.
  Future<void> _upsertProfile(String id, String name) async {
    try {
      await _supabase.from('profiles').upsert({'id': id, 'name': name});
    } catch (_) {}
  }

  /// Tulis cermin token + profil ke [TokenStorage], kembalikan sesi
  /// dalam bentuk model aplikasi.
  Future<AuthSession> _mirrorSession(Session session, AppUser user) async {
    await _storage.saveTokens(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken ?? '',
    );
    await _storage.saveUser(user);
    return AuthSession(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken ?? '',
      user: user,
    );
  }

  /// Pesan error Supabase → pesan aplikasi (Indonesia bila dikenal).
  String _authMessage(AuthException e) {
    final msg = e.message;
    if (msg.toLowerCase().contains('invalid login credentials')) {
      return 'Email atau password salah';
    }
    if (msg.toLowerCase().contains('already registered')) {
      return 'Email sudah terdaftar';
    }
    return msg;
  }
}

/// Tambahan penyimpanan profil user di secure storage.
extension UserStorageX on TokenStorage {
  static const _userKey = 'worthbang_user_json';
  static const _biometricKey = 'worthbang_biometric_enabled';

  Future<void> saveUser(AppUser user) => writeRaw(
        _userKey,
        const JsonEncoder().convert(user.toJson()),
      );

  Future<AppUser?> readUser() async {
    final raw = await readRaw(_userKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return AppUser.fromJson(
        const JsonDecoder().convert(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> isBiometricEnabled() async =>
      (await readRaw(_biometricKey)) == '1';

  Future<void> setBiometricEnabled(bool enabled) =>
      writeRaw(_biometricKey, enabled ? '1' : '0');
}
