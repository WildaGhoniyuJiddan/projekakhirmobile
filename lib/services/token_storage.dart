import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Interface key-value aman — memutus ketergantungan langsung ke
/// [FlutterSecureStorage] agar [TokenStorage] bisa di-test tanpa platform.
abstract class SecureKv {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> clear();
}

/// Implementasi produksi di atas flutter_secure_storage (Keystore/Keychain).
class FlutterSecureKv implements SecureKv {
  FlutterSecureKv([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> clear() => _storage.deleteAll();
}

/// Implementasi in-memory — HANYA untuk test.
class MemorySecureKv implements SecureKv {
  final _map = <String, String>{};

  @override
  Future<String?> read(String key) async => _map[key];

  @override
  Future<void> write(String key, String value) async {
    _map[key] = value;
  }

  @override
  Future<void> clear() async => _map.clear();
}

/// Penyimpanan token auth.
///
/// ATURAN KEAMANAN: token HANYA boleh disimpan via [SecureKv]
/// (produksi: Keychain/Keystore terenkripsi). DILARANG menyimpan token di
/// SharedPreferences, file biasa, atau log.
class TokenStorage {
  TokenStorage([SecureKv? kv]) : _kv = kv ?? FlutterSecureKv();

  final SecureKv _kv;

  static const _accessTokenKey = 'worthbang_access_token';
  static const _refreshTokenKey = 'worthbang_refresh_token';

  Future<String?> readAccessToken() => _kv.read(_accessTokenKey);

  Future<String?> readRefreshToken() => _kv.read(_refreshTokenKey);

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _kv.write(_accessTokenKey, accessToken);
    await _kv.write(_refreshTokenKey, refreshToken);
  }

  /// Hapus semua token — dipakai saat logout / refresh gagal.
  Future<void> clear() => _kv.clear();

  /// Akses mentah untuk data non-token (profil user JSON, flag biometric).
  /// Tetap di secure storage agar konsisten keamanannya.
  Future<String?> readRaw(String key) => _kv.read(key);

  Future<void> writeRaw(String key, String value) => _kv.write(key, value);
}
