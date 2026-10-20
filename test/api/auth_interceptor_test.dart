import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthbang/services/api_exception.dart';
import 'package:worthbang/services/dio_api_client.dart';
import 'package:worthbang/services/token_storage.dart';


/// Adapter HTTP palsu: kembalikan response sesuai skenario test.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  /// Snapshot (path, Authorization header) tiap panggilan — disalin saat
  /// fetch karena Dio memakai ulang objek RequestOptions yang sama.
  final List<({String path, String? auth})> calls = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    calls.add((path: options.path, auth: options.headers['Authorization'] as String?));
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object data, int statusCode) => ResponseBody.fromString(
      jsonEncode(data),
      statusCode,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );

void main() {
  group('Auth interceptor (DioApiClient)', () {
    test('401 → refresh sekali → retry request asli dengan token baru',
        () async {
      final storage = TokenStorage(MemorySecureKv());
      await storage.saveTokens(
        accessToken: 'access-lama',
        refreshToken: 'refresh-valid',
      );

      final adapter = _FakeAdapter((options) async {
        if (options.path == '/api/v1/history') {
          // Request pertama 401 (token kedaluwarsa), retry-nya 200.
          final auth = options.headers['Authorization'] as String?;
          if (auth == 'Bearer access-baru') {
            return _json({'items': []}, 200);
          }
          return _json({'detail': 'Token kedaluwarsa'}, 401);
        }
        if (options.path == '/api/v1/auth/refresh') {
          return _json({
            'access_token': 'access-baru',
            'refresh_token': 'refresh-baru',
            'token_type': 'bearer',
          }, 200);
        }
        return _json({'detail': 'not found'}, 404);
      });

      final dio = Dio(BaseOptions(baseUrl: devBaseUrl))
        ..httpClientAdapter = adapter;
      final client = DioApiClient(tokenStorage: storage, dio: dio);

      final result = await client.getJson('/api/v1/history');

      expect(result, {'items': []});
      // Refresh dipanggil tepat sekali.
      expect(
        adapter.calls.where((c) => c.path == '/api/v1/auth/refresh'),
        hasLength(1),
      );
      // Request asli diulang dengan bearer token BARU.
      final historyCalls =
          adapter.calls.where((c) => c.path == '/api/v1/history').toList();
      expect(historyCalls, hasLength(2));
      expect(historyCalls[0].auth, 'Bearer access-lama');
      expect(historyCalls[1].auth, 'Bearer access-baru');
      // Token baru tersimpan di secure storage.
      expect(await storage.readAccessToken(), 'access-baru');
      expect(await storage.readRefreshToken(), 'refresh-baru');

      client.close();
    });

    test('refresh gagal (401) → token dihapus & event logout terpancar',
        () async {
      final storage = TokenStorage(MemorySecureKv());
      await storage.saveTokens(
        accessToken: 'access-lama',
        refreshToken: 'refresh-basi',
      );

      final adapter = _FakeAdapter((options) async {
        if (options.path == '/api/v1/auth/refresh') {
          return _json({'detail': 'Refresh token tidak valid'}, 401);
        }
        return _json({'detail': 'Unauthorized'}, 401);
      });

      final dio = Dio(BaseOptions(baseUrl: devBaseUrl))
        ..httpClientAdapter = adapter;
      final client = DioApiClient(tokenStorage: storage, dio: dio);

      final logoutEvents = <void>[];
      final sub = client.onForceLogout.listen(logoutEvents.add);

      await expectLater(
        client.getJson('/api/v1/history'),
        throwsA(isA<ApiException>().having(
          (e) => e.statusCode,
          'statusCode',
          401,
        )),
      );

      // Refresh hanya dicoba sekali (tidak loop).
      expect(
        adapter.calls.where((c) => c.path == '/api/v1/auth/refresh'),
        hasLength(1),
      );
      // Token dibersihkan & event logout terpancar tepat sekali.
      expect(await storage.readAccessToken(), isNull);
      expect(await storage.readRefreshToken(), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(logoutEvents, hasLength(1));

      await sub.cancel();
      client.close();
    });

    test('endpoint auth publik tidak dikirim Authorization header', () async {
      final storage = TokenStorage(MemorySecureKv());
      await storage.saveTokens(
        accessToken: 'access-ada',
        refreshToken: 'refresh-ada',
      );

      final adapter = _FakeAdapter((options) async {
        return _json({
          'access_token': 'a',
          'refresh_token': 'r',
          'token_type': 'bearer',
        }, 200);
      });

      final dio = Dio(BaseOptions(baseUrl: devBaseUrl))
        ..httpClientAdapter = adapter;
      final client = DioApiClient(tokenStorage: storage, dio: dio);

      await client.postJson('/api/v1/auth/login',
          body: {'email': 'a@b.c', 'password': 'x'});

      expect(adapter.calls.single.auth, isNull);
      client.close();
    });

    test('ekstraksi pesan error FastAPI list detail ke ApiException', () async {
      final storage = TokenStorage(MemorySecureKv());
      final adapter = _FakeAdapter((options) async {
        return _json({
          'detail': [
            {'loc': ['body', 'price'], 'msg': 'Input should be greater than 0', 'type': 'greater_than'},
          ],
        }, 422);
      });

      final dio = Dio(BaseOptions(baseUrl: devBaseUrl))
        ..httpClientAdapter = adapter;
      final client = DioApiClient(tokenStorage: storage, dio: dio);

      expect(
        () => client.postJson('/api/v1/test', body: {}),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 422)
            .having((e) => e.message, 'message', 'Input should be greater than 0')),
      );
      client.close();
    });
  });
}
