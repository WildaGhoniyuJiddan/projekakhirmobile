import 'dart:async';

/// Kontrak HTTP client aplikasi.
///
/// Diimplementasikan oleh [DioApiClient] (produksi) dan [FakeApiClient]
/// (demo/test) — keduanya mengikuti bentuk request/response di
/// API_CONTRACT.md.
abstract class ApiClient {
  /// Emit sekali setiap refresh token gagal (401) → UI wajib logout paksa.
  Stream<void> get onForceLogout;

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? query,
  });

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
  });

  Future<void> delete(String path);

  /// PUT multipart (upload file). [fields] = form text, [files] = field → path file lokal.
  Future<Map<String, dynamic>> putMultipart(
    String path, {
    Map<String, String>? fields,
    Map<String, String>? files,
  });

  /// Bebaskan resource (stream controller, dsb).
  void close();
}
