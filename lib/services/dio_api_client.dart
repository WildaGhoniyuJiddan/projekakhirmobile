import 'dart:async';

import 'package:dio/dio.dart';

import 'package:worthbang/services/token_storage.dart';
import 'api_client.dart';
import 'api_exception.dart';

/// Base URL backend saat development (emulator Android → host loopback).
const String devBaseUrl = 'http://10.0.2.2:8000';

/// Bisa diarahkan ke backend pada komputer host saat dites dari HP fisik.
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: devBaseUrl,
);

/// [ApiClient] produksi di atas Dio.
///
/// - Menyematkan `Authorization: Bearer <access_token>` di tiap request
///   (kecuali endpoint auth publik).
/// - Saat menerima 401: refresh token SEKALI via
///   `POST /api/v1/auth/refresh`, lalu ulangi request asli.
/// - Bila refresh gagal (401 / error jaringan): hapus token dan emit
///   [onForceLogout] agar UI logout paksa (sesuai API_CONTRACT.md B1).
class DioApiClient implements ApiClient {
  DioApiClient({
    required this._tokenStorage,
    String baseUrl = apiBaseUrl,
    Dio? dio,
  })  : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
              contentType: Headers.jsonContentType,
              responseType: ResponseType.json,
            )) {
    // Dio refresh khusus TANPA interceptor auth (hindari loop 401).
    _refreshDio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
    ));
    if (dio?.httpClientAdapter case final adapter?) {
      _refreshDio.httpClientAdapter = adapter;
    }
    _dio.interceptors.add(_AuthInterceptor(this));
  }

  final TokenStorage _tokenStorage;
  final Dio _dio;
  late final Dio _refreshDio;
  final _logoutController = StreamController<void>.broadcast();

  /// Refresh yang sedang berjalan — request 401 bersamaan ikut menunggu
  /// refresh yang sama, bukan memicu refresh ganda.
  Future<bool>? _refreshInFlight;

  @override
  Stream<void> get onForceLogout => _logoutController.stream;

  /// Endpoint publik yang tidak butuh (dan tidak boleh dikirim) bearer token.
  static bool isPublicAuthEndpoint(String path) =>
      path.startsWith('/api/v1/auth/login') ||
      path.startsWith('/api/v1/auth/register') ||
      path.startsWith('/api/v1/auth/refresh');

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: query,
      );
      return res.data ?? const {};
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(path, data: body);
      return res.data ?? const {};
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  @override
  @override
  Future<void> delete(String path) async {
    try {
      await _dio.delete<void>(path);
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> putMultipart(
    String path, {
    Map<String, String>? fields,
    Map<String, String>? files,
  }) async {
    try {
      final form = FormData.fromMap({
        ...?fields,
        if (files != null)
          for (final e in files.entries)
            e.key: await MultipartFile.fromFile(e.value),
      });
      final res = await _dio.put<Map<String, dynamic>>(path, data: form);
      return res.data ?? {};
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  @override
  void close() {
    _logoutController.close();
    _dio.close();
    _refreshDio.close();
  }

  /// Coba refresh token sekali. Mengembalikan true bila token baru tersimpan.
  Future<bool> _refreshTokens() {
    _refreshInFlight ??= _doRefresh().whenComplete(() => _refreshInFlight = null);
    return _refreshInFlight!;
  }

  Future<bool> _doRefresh() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return false;
    try {
      final res = await _refreshDio.post<Map<String, dynamic>>(
        '/api/v1/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      final data = res.data ?? const {};
      final access = data['access_token'] as String?;
      final refresh = data['refresh_token'] as String?;
      if (access == null || refresh == null) return false;
      await _tokenStorage.saveTokens(
        accessToken: access,
        refreshToken: refresh,
      );
      return true;
    } on DioException {
      return false;
    }
  }

  Future<void> _forceLogout() async {
    await _tokenStorage.clear();
    if (!_logoutController.isClosed) _logoutController.add(null);
  }

  ApiException _toApiException(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    var message = 'Terjadi kesalahan jaringan. Coba lagi.';
    if (data is Map) {
      final detail = data['detail'];
      if (detail is String && detail.isNotEmpty) {
        message = detail;
      } else if (detail is List && detail.isNotEmpty) {
        final messages = <String>[];
        for (final item in detail) {
          if (item is Map && item['msg'] != null) {
            messages.add(item['msg'].toString());
          } else if (item != null) {
            messages.add(item.toString());
          }
        }
        if (messages.isNotEmpty) {
          message = messages.join('\n');
        }
      } else if (data['message'] is String &&
          (data['message'] as String).isNotEmpty) {
        message = data['message'] as String;
      }
    } else if (data is String && data.isNotEmpty) {
      message = data;
    } else if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      message =
          'Koneksi ke server timeout. Pastikan backend aktif dan alamat API benar. '
          'Jika memakai HP fisik, gunakan IP LAN komputer.';
    } else if (e.type == DioExceptionType.connectionError) {
      message =
          'Tidak dapat terhubung ke server. Pastikan backend aktif dan alamat API benar.';
    }
    return ApiException(message, status);
  }
}

/// Interceptor auth: sematkan bearer token & tangani 401 → refresh → retry.
class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._client);

  final DioApiClient _client;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!DioApiClient.isPublicAuthEndpoint(options.path)) {
      final token = await _client._tokenStorage.readAccessToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final req = err.requestOptions;
    final alreadyRetried = req.extra['auth_retried'] == true;

    if (err.response?.statusCode == 401 &&
        !alreadyRetried &&
        !DioApiClient.isPublicAuthEndpoint(req.path)) {
      final refreshed = await _client._refreshTokens();
      if (refreshed) {
        // Ulangi request asli sekali dengan token baru.
        req.extra['auth_retried'] = true;
        try {
          final response = await _client._dio.fetch<Map<String, dynamic>>(req);
          return handler.resolve(response);
        } on DioException catch (retryErr) {
          return handler.next(retryErr);
        }
      }
      // Refresh gagal → logout paksa.
      await _client._forceLogout();
    }
    handler.next(err);
  }
}
