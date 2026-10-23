import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:worthbang/l10n/strings.dart';
import 'package:worthbang/models/store_models.dart';
import 'package:worthbang/screens/stores_screen.dart';
import 'package:worthbang/services/core/api_result.dart';
import 'package:worthbang/services/features/routing_service.dart';
import 'package:worthbang/services/features/stores_api.dart';
import 'package:worthbang/utils/theme.dart';

/// Posisi pengguna palsu (Yogyakarta) untuk seluruh test.
final _userPos = Position(
  latitude: -7.7700,
  longitude: 110.3600,
  timestamp: DateTime(2026, 10, 23),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 90,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

class _FakeGeolocatorPlatform extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async =>
      _userPos;

  @override
  Stream<Position> getPositionStream({
    LocationSettings? locationSettings,
  }) =>
      Stream<Position>.fromIterable([_userPos]);
}

const _store = Store(
  id: 1,
  name: 'Toko Uji',
  address: 'Jl. Uji No. 1',
  lat: -7.7800,
  lng: 110.3700,
  distanceKm: 1.5,
  prices: {},
);

class _FakeStoresApi extends StoresApi {
  @override
  Future<List<Store>> nearby({
    required double lat,
    required double lng,
    double radiusKm = 25,
    String? query,
  }) async =>
      [_store];
}

class _FakeRoutingService extends RoutingService {
  @override
  Future<ApiResult<RouteResult>> fetchRoute({
    required LatLng from,
    required LatLng to,
  }) async =>
      ApiSuccess(
        RouteResult(
          points: [
            from,
            LatLng(
              (from.latitude + to.latitude) / 2,
              (from.longitude + to.longitude) / 2,
            ),
            to,
          ],
          distanceMeters: 1500,
          durationSeconds: 360,
        ),
      );
}

Future<void> _pumpFrames(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GeolocatorPlatform.instance = _FakeGeolocatorPlatform();
  });

  testWidgets('ketuk toko → kartu detail; mulai navigasi → polyline + panel',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storesApiProvider.overrideWithValue(_FakeStoresApi()),
          routingServiceProvider.overrideWithValue(_FakeRoutingService()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const StoresScreen(),
        ),
      ),
    );
    await _pumpFrames(tester);

    // Daftar toko tampil; belum ada kartu detail/navigasi.
    expect(find.text('Toko Uji'), findsWidgets);
    expect(find.text(AppStrings.navigateToStoreButton), findsNothing);

    // Ketuk item toko → kartu detail + tombol navigasi muncul.
    await tester.tap(find.text('Toko Uji').first);
    await _pumpFrames(tester, 4);
    expect(find.text(AppStrings.navigateToStoreButton), findsOneWidget);
    expect(find.text('Jl. Uji No. 1'), findsWidgets);

    // Mulai navigasi (routing palsu) → polyline + panel navigasi tampil.
    await tester.tap(find.text(AppStrings.navigateToStoreButton));
    await _pumpFrames(tester);
    expect(find.byType(PolylineLayer), findsOneWidget);
    expect(find.text(AppStrings.endNavigationButton), findsOneWidget);
    expect(
      find.textContaining(AppStrings.remainingDistanceLabel),
      findsOneWidget,
    );

    // Akhiri navigasi → panel hilang, kartu detail kembali.
    await tester.tap(find.text(AppStrings.endNavigationButton));
    await _pumpFrames(tester, 4);
    expect(find.byType(PolylineLayer), findsNothing);
    expect(find.text(AppStrings.navigateToStoreButton), findsOneWidget);
  });
}
