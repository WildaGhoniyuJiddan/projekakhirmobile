import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'package:worthbang/services/core/api_result.dart';

final routingServiceProvider = Provider<RoutingService>(
  (ref) => RoutingService(),
);

/// Hasil rute berkendara dari OSRM: geometri jalan + jarak + durasi.
class RouteResult {
  const RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  /// Titik-titik garis rute, dari asal ke tujuan.
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
}

/// Klien rute OSRM publik (profil berkendara saja, sesuai keputusan Dan).
///
/// Kegagalan selalu menjadi [ApiError] dengan pesan Bahasa Indonesia —
/// pemanggil memutuskan fallback (garis penunjuk lurus), tidak pernah
/// diam-diam kosong.
class RoutingService {
  RoutingService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              responseType: ResponseType.json,
            ));

  final Dio _dio;

  static const _baseUrl = 'https://router.project-osrm.org/route/v1/driving';

  /// Ambil rute berkendara [from] → [to] dari OSRM.
  Future<ApiResult<RouteResult>> fetchRoute({
    required LatLng from,
    required LatLng to,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        '$_baseUrl/${from.longitude},${from.latitude};'
        '${to.longitude},${to.latitude}',
        queryParameters: const {
          'overview': 'full',
          'geometries': 'geojson',
        },
      );
      final parsed = parseOsrmRoute(response.data);
      if (parsed == null) {
        return const ApiError('Rute tidak ditemukan untuk tujuan ini.');
      }
      return ApiSuccess(parsed);
    } on DioException catch (e) {
      return ApiError('Rute jalan tidak dapat dimuat (${e.message ?? e.type}).');
    } catch (e) {
      return ApiError('Rute jalan tidak dapat dimuat: $e');
    }
  }

  /// Parse badan JSON OSRM menjadi [RouteResult]; null bila tidak ada
  /// rute yang valid (routes kosong / geometri < 2 titik). Murni —
  /// dipakai juga oleh test tanpa jaringan.
  static RouteResult? parseOsrmRoute(Object? data) {
    if (data is! Map) return null;
    final routes = data['routes'];
    if (routes is! List || routes.isEmpty) return null;
    final route = routes.first;
    if (route is! Map) return null;
    final geometry = route['geometry'];
    if (geometry is! Map) return null;
    final coords = geometry['coordinates'];
    if (coords is! List || coords.length < 2) return null;
    final points = <LatLng>[];
    for (final c in coords) {
      if (c is List && c.length >= 2 && c[0] is num && c[1] is num) {
        // GeoJSON: [lng, lat] → LatLng(lat, lng).
        points.add(LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()));
      }
    }
    if (points.length < 2) return null;
    return RouteResult(
      points: points,
      distanceMeters: (route['distance'] as num?)?.toDouble() ?? 0,
      durationSeconds: (route['duration'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Kemajuan posisi [point] terhadap [route]:
/// - `toRouteMeters`: jarak tegak lurus terdekat ke garis rute.
/// - `remainingMeters`: jarak menyusuri rute dari titik proyeksi
///   terdekat sampai ujung rute (tujuan).
///
/// Proyeksi dihitung di ruang meter lokal (equirectangular di sekitar
/// [point]) — cukup akurat untuk segmen jalan pendek.
({double toRouteMeters, double remainingMeters}) routeProgress(
  List<LatLng> route,
  LatLng point,
) {
  const distance = Distance();
  if (route.isEmpty) return (toRouteMeters: double.infinity, remainingMeters: 0);
  if (route.length == 1) {
    final d = distance.as(LengthUnit.Meter, point, route.first).toDouble();
    return (toRouteMeters: d, remainingMeters: 0);
  }

  // Panjang tiap segmen + total, untuk sisa jarak menyusuri rute.
  final segLens = <double>[];
  var total = 0.0;
  for (var i = 0; i < route.length - 1; i++) {
    final len = distance
        .as(LengthUnit.Meter, route[i], route[i + 1])
        .toDouble();
    segLens.add(len);
    total += len;
  }

  // Skala derajat → meter di sekitar titik pengguna.
  final kx = 111320.0 * math.cos(point.latitude * math.pi / 180);
  final ky = 110540.0;
  double xOf(LatLng p) => (p.longitude - point.longitude) * kx;
  double yOf(LatLng p) => (p.latitude - point.latitude) * ky;

  var bestToRoute = double.infinity;
  var bestRemaining = total;
  var travelled = 0.0;
  for (var i = 0; i < route.length - 1; i++) {
    final ax = xOf(route[i]);
    final ay = yOf(route[i]);
    final bx = xOf(route[i + 1]);
    final by = yOf(route[i + 1]);
    final dx = bx - ax;
    final dy = by - ay;
    final lenSq = dx * dx + dy * dy;
    // Titik pengguna adalah origin (0,0) di ruang lokal ini.
    var t = lenSq == 0 ? 0.0 : (-(ax * dx + ay * dy)) / lenSq;
    t = t.clamp(0.0, 1.0);
    final cx = ax + t * dx;
    final cy = ay + t * dy;
    final d = math.sqrt(cx * cx + cy * cy);
    if (d < bestToRoute) {
      bestToRoute = d;
      bestRemaining = total - travelled - t * segLens[i];
    }
    travelled += segLens[i];
  }
  return (toRouteMeters: bestToRoute, remainingMeters: bestRemaining);
}
