import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:worthbang/services/core/api_result.dart';
import 'package:worthbang/services/features/routing_service.dart';

/// Adapter dio palsu: mengembalikan fixture tanpa jaringan beneran.
class _FixtureAdapter implements HttpClientAdapter {
  _FixtureAdapter(this.body);

  final Object body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _ThrowingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      message: 'offline',
    );
  }

  @override
  void close({bool force = false}) {}
}

RoutingService _serviceWith(HttpClientAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return RoutingService(dio: dio);
}

/// Fixture OSRM mini: rute 3 titik di sekitar Yogyakarta.
final _osrmFixture = {
  'code': 'Ok',
  'routes': [
    {
      'distance': 1234.5,
      'duration': 345.6,
      'geometry': {
        'type': 'LineString',
        'coordinates': [
          [110.3600, -7.7700],
          [110.3650, -7.7750],
          [110.3700, -7.7800],
        ],
      },
    },
  ],
};

void main() {
  group('RoutingService.fetchRoute', () {
    test('parse OSRM: titik (lng,lat → LatLng), jarak, durasi', () async {
      final service = _serviceWith(_FixtureAdapter(_osrmFixture));
      final result = await service.fetchRoute(
        from: const LatLng(-7.77, 110.36),
        to: const LatLng(-7.78, 110.37),
      );

      expect(result, isA<ApiSuccess<RouteResult>>());
      final route = (result as ApiSuccess<RouteResult>).data;
      expect(route.points, hasLength(3));
      expect(route.points.first.latitude, closeTo(-7.77, 1e-9));
      expect(route.points.first.longitude, closeTo(110.36, 1e-9));
      expect(route.points.last.latitude, closeTo(-7.78, 1e-9));
      expect(route.points.last.longitude, closeTo(110.37, 1e-9));
      expect(route.distanceMeters, 1234.5);
      expect(route.durationSeconds, 345.6);
    });

    test('routes kosong → ApiError', () async {
      final service = _serviceWith(_FixtureAdapter({'routes': []}));
      final result = await service.fetchRoute(
        from: const LatLng(-7.77, 110.36),
        to: const LatLng(-7.78, 110.37),
      );
      expect(result, isA<ApiError<RouteResult>>());
    });

    test('jaringan gagal (DioException) → ApiError', () async {
      final service = _serviceWith(_ThrowingAdapter());
      final result = await service.fetchRoute(
        from: const LatLng(-7.77, 110.36),
        to: const LatLng(-7.78, 110.37),
      );
      expect(result, isA<ApiError<RouteResult>>());
    });
  });

  group('routeProgress', () {
    // Rute lurus ke timur: ±1,1 km.
    final route = [
      const LatLng(-7.77, 110.36),
      const LatLng(-7.77, 110.37),
    ];

    test('titik di tengah rute: jarak ke rute ±0, sisa ±setengah rute',
        () {
      final p = routeProgress(route, const LatLng(-7.77, 110.365));
      expect(p.toRouteMeters, closeTo(0, 1));
      final total = const Distance()
          .as(LengthUnit.Meter, route.first, route.last)
          .toDouble();
      expect(p.remainingMeters, closeTo(total / 2, total * 0.05));
    });

    test('titik melenceng ke utara: jarak ke rute ≈ jarak tegak lurus',
        () {
      // ±0,005° ke utara ≈ 553 m dari garis rute.
      final p = routeProgress(route, const LatLng(-7.765, 110.365));
      expect(p.toRouteMeters, greaterThan(450));
      expect(p.toRouteMeters, lessThan(650));
    });

    test('titik di tujuan: sisa jarak ±0', () {
      final p = routeProgress(route, const LatLng(-7.77, 110.37));
      expect(p.remainingMeters, closeTo(0, 1));
    });
  });
}
