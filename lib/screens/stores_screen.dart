import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:worthbang/services/core/api_result.dart';
import 'package:worthbang/core/theme/monex_theme.dart';
import 'package:worthbang/core/widgets/monex_widgets.dart';
import 'package:worthbang/l10n/strings.dart';
import 'package:worthbang/models/store_models.dart';
import 'package:worthbang/services/features/routing_service.dart';
import 'package:worthbang/services/features/stores_api.dart';

/// Koordinat fallback (demo Jakarta) bila izin lokasi ditolak / gagal.
const _demoLat = -6.2088;
const _demoLng = 106.8456;

/// Zoom kamera saat mode navigasi mengikuti pengguna.
const _navZoom = 17.0;

/// Jarak melenceng dari garis rute yang memicu hitung ulang rute.
const _offRouteThresholdMeters = 50.0;

/// Jarak ke toko yang dianggap sudah tiba.
const _arrivalThresholdMeters = 30.0;

/// Layar Toko Terdekat: peta + daftar termurah untuk produk yang dicari.
class StoresScreen extends ConsumerStatefulWidget {
  const StoresScreen({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  ConsumerState<StoresScreen> createState() => _StoresScreenState();
}

class _StoresScreenState extends ConsumerState<StoresScreen>
    with SingleTickerProviderStateMixin {
  final _query = TextEditingController();
  final _mapController = MapController();
  ApiResult<List<Store>>? _state;
  LatLng _center = const LatLng(_demoLat, _demoLng);
  bool _usingDemoLocation = true;
  bool _mapReady = false;
  bool _isLocating = false;
  String? _locationMessage;

  // --- Pilihan toko & navigasi rute ---
  Store? _selectedStore;
  bool _calculatingRoute = false;
  bool _navigating = false;
  bool _routeIsFallback = false;
  bool _followUser = true;
  bool _arrived = false;
  List<LatLng> _routePoints = const [];
  double _routeDistanceMeters = 0;
  double _routeDurationSeconds = 0;
  double _remainingMeters = 0;
  double _etaSeconds = 0;
  DateTime? _lastRerouteAt;
  bool _rerouting = false;

  // --- Titik pengguna live (hanya selama navigasi) ---
  StreamSubscription<Position>? _positionSub;
  late final AnimationController _markerAnim;
  LatLng _displayPosition = const LatLng(_demoLat, _demoLng);
  LatLng _animFrom = const LatLng(_demoLat, _demoLng);
  LatLng _animTo = const LatLng(_demoLat, _demoLng);
  double? _headingDeg;

  @override
  void initState() {
    super.initState();
    _query.text = widget.initialQuery;
    _markerAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..addListener(_onMarkerAnimTick);
    _locateAndLoad();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _markerAnim.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _locateAndLoad() async {
    if (_isLocating) return;
    setState(() {
      _isLocating = true;
      _locationMessage = null;
    });
    String? locationMessage;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        locationMessage =
            'Aktifkan layanan lokasi/GPS untuk memakai lokasi Anda.';
        return;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }

      if (perm == LocationPermission.deniedForever) {
        locationMessage = 'Izin lokasi diblokir. Buka Pengaturan aplikasi untuk mengizinkannya.';
        return;
      }

      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        locationMessage =
            'Izin lokasi ditolak. Peta tetap memakai lokasi demo Jakarta.';
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      ).timeout(const Duration(seconds: 12));
      if (!mounted) return;
      final location = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _center = location;
        _usingDemoLocation = false;
      });
      if (_mapReady) _mapController.move(location, 13);
    } on LocationServiceDisabledException {
      locationMessage =
          'Aktifkan layanan lokasi/GPS untuk memakai lokasi Anda.';
    } on TimeoutException {
      locationMessage =
          'Lokasi belum ditemukan. Pastikan GPS aktif lalu coba lagi.';
    } catch (e) {
      locationMessage = 'Lokasi gagal didapatkan: $e';
    } finally {
      if (mounted) {
        setState(() {
          _isLocating = false;
          _locationMessage = locationMessage;
        });
        await _load();
      }
    }
  }

  Future<void> _load() async {
    setState(() => _state = const ApiLoading());
    try {
      final stores = await ref
          .read(storesApiProvider)
          .nearby(
            lat: _center.latitude,
            lng: _center.longitude,
            query: _query.text.trim(),
          );
      if (!mounted) return;
      setState(() => _state = ApiSuccess(stores));
    } catch (e) {
      if (!mounted) return;
      setState(() => _state = ApiError(e.toString()));
    }
  }

  Future<void> _openLocationSettings() async {
    final opened = await Geolocator.openAppSettings();
    if (!opened && mounted) {
      showMonexToast(
        context,
        'Pengaturan aplikasi tidak dapat dibuka.',
        isError: true,
      );
    }
  }

  // ==========================================================================
  // Pilihan toko & navigasi rute
  // ==========================================================================

  /// Pilih toko (dari pin peta atau item daftar): kamera ke toko dan
  /// kartu detailnya tampil. Memilih saat navigasi berjalan mengakhiri
  /// navigasi yang lama lebih dulu.
  void _selectStore(Store store) {
    if (_navigating) _stopNavigation();
    setState(() => _selectedStore = store);
    if (_mapReady) {
      _mapController.move(LatLng(store.lat, store.lng), 15);
    }
  }

  Future<void> _startNavigation() async {
    final store = _selectedStore;
    if (store == null || _calculatingRoute) return;
    // Navigasi butuh posisi asli — lokasi demo tidak bisa dinavigasikan.
    if (_usingDemoLocation) {
      showMonexToast(context, AppStrings.navigationNeedsLocation,
          isError: true);
      _locateAndLoad();
      return;
    }
    setState(() => _calculatingRoute = true);
    final origin = _center;
    final dest = LatLng(store.lat, store.lng);
    final result = await ref
        .read(routingServiceProvider)
        .fetchRoute(from: origin, to: dest);
    if (!mounted) return;

    final List<LatLng> points;
    final double distanceMeters;
    final double durationSeconds;
    final bool fallback;
    switch (result) {
      case ApiSuccess(:final data):
        points = data.points;
        distanceMeters = data.distanceMeters;
        durationSeconds = data.durationSeconds;
        fallback = false;
      case ApiError():
        // Zero silent failure: beri tahu pengguna, tetap navigasikan
        // dengan garis penunjuk lurus asal → tujuan.
        fallback = true;
        points = [origin, dest];
        distanceMeters =
            const Distance().as(LengthUnit.Meter, origin, dest).toDouble();
        // Estimasi kasar berkendara 30 km/jam untuk garis penunjuk.
        durationSeconds = distanceMeters / (30000 / 3600);
        showMonexToast(context, AppStrings.routeFallbackToast, isError: true);
      case ApiLoading():
        setState(() => _calculatingRoute = false);
        return;
    }

    setState(() {
      _calculatingRoute = false;
      _navigating = true;
      _followUser = true;
      _arrived = false;
      _routeIsFallback = fallback;
      _routePoints = points;
      _routeDistanceMeters = distanceMeters;
      _routeDurationSeconds = durationSeconds;
      _remainingMeters = distanceMeters;
      _etaSeconds = durationSeconds;
      _lastRerouteAt = null;
      _displayPosition = origin;
      _animFrom = origin;
      _animTo = origin;
    });
    _subscribePosition();
    if (_mapReady) _mapController.move(origin, _navZoom);
  }

  void _stopNavigation() {
    _positionSub?.cancel();
    _positionSub = null;
    _markerAnim.stop();
    setState(() {
      _navigating = false;
      _routePoints = const [];
      _routeIsFallback = false;
      _followUser = true;
      _arrived = false;
    });
  }

  void _subscribePosition() {
    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(
      _onPosition,
      onError: (Object e) {
        if (!mounted || !_navigating) return;
        setState(() => _locationMessage = 'Sinyal GPS terganggu: $e');
      },
    );
  }

  void _onPosition(Position pos) {
    if (!mounted || !_navigating) return;
    if (pos.speed > 0 && pos.heading >= 0) {
      _headingDeg = pos.heading;
    }
    final target = LatLng(pos.latitude, pos.longitude);
    _animateMarkerTo(target);
    _updateProgress(target);
  }

  /// Titik pengguna tidak melompat: setiap fix GPS baru dianimasikan
  /// meluncur linear (±900 ms) dari posisi tampil saat ini ke fix baru.
  void _animateMarkerTo(LatLng target) {
    _animFrom = _displayPosition;
    _animTo = target;
    _markerAnim.forward(from: 0);
  }

  void _onMarkerAnimTick() {
    if (!mounted) return;
    final t = _markerAnim.value;
    final next = LatLng(
      _animFrom.latitude + (_animTo.latitude - _animFrom.latitude) * t,
      _animFrom.longitude + (_animTo.longitude - _animFrom.longitude) * t,
    );
    setState(() => _displayPosition = next);
    if (_navigating && _followUser && _mapReady) {
      _mapController.move(next, _navZoom);
    }
  }

  /// Sisa jarak & estimasi waktu yang hidup + deteksi tiba/melenceng.
  void _updateProgress(LatLng pos) {
    final store = _selectedStore;
    if (store == null) return;
    final dest = LatLng(store.lat, store.lng);

    final arrivedNow = !_arrived &&
        const Distance().as(LengthUnit.Meter, pos, dest) <
            _arrivalThresholdMeters;
    if (arrivedNow) {
      showMonexToast(
        context,
        '${AppStrings.arrivedAtPrefix} ${store.name}',
        isSuccess: true,
      );
    }

    if (_routePoints.length < 2) {
      if (arrivedNow) setState(() => _arrived = true);
      return;
    }
    final progress = routeProgress(_routePoints, pos);
    final cap =
        _routeDistanceMeters > 0 ? _routeDistanceMeters : progress.remainingMeters;
    final remaining = progress.remainingMeters.clamp(0.0, cap);
    setState(() {
      if (arrivedNow) _arrived = true;
      _remainingMeters = remaining;
      _etaSeconds = _routeDistanceMeters > 0
          ? _routeDurationSeconds * (remaining / _routeDistanceMeters)
          : 0;
    });

    // Melenceng jauh dari garis rute → hitung ulang dari posisi sekarang
    // (dijeda minimal 10 detik antar permintaan).
    if (progress.toRouteMeters > _offRouteThresholdMeters) {
      final now = DateTime.now();
      final last = _lastRerouteAt;
      if (!_rerouting &&
          (last == null || now.difference(last).inSeconds >= 10)) {
        _lastRerouteAt = now;
        _reroute(pos, dest);
      }
    }
  }

  Future<void> _reroute(LatLng from, LatLng dest) async {
    _rerouting = true;
    showMonexToast(context, AppStrings.recalculatingRoute);
    final result = await ref
        .read(routingServiceProvider)
        .fetchRoute(from: from, to: dest);
    _rerouting = false;
    if (!mounted || !_navigating) return;
    if (result case ApiSuccess(:final data)) {
      setState(() {
        _routePoints = data.points;
        _routeDistanceMeters = data.distanceMeters;
        _routeDurationSeconds = data.durationSeconds;
        _routeIsFallback = false;
      });
      _updateProgress(from);
    }
    // Gagal hitung ulang: rute lama dipertahankan (toast sudah tampil).
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final stores = state is ApiSuccess<List<Store>> ? state.data : null;
    final q = _query.text.trim().toLowerCase();
    final filteredStores = (stores ?? []).where((s) {
      if (q.isEmpty) return true;
      return s.name.toLowerCase().contains(q) ||
          s.address.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.storesTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _query,
                      decoration: InputDecoration(
                        labelText: AppStrings.searchStoreLabel,
                        hintText: AppStrings.searchStoreHint,
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _query.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _query.clear();
                                  setState(() {});
                                  _load();
                                },
                              )
                            : null,
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _load(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  MonexPrimaryButton(
                    onPressed: state is ApiLoading ? null : _load,
                    label: AppStrings.refreshLabel,
                    expanded: false,
                    loading: state is ApiLoading,
                  ),
                ],
              ),
            ),
            if (_usingDemoLocation || _locationMessage != null)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _locationMessage ?? AppStrings.demoLocationNote,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (_locationMessage?.contains('Pengaturan') ?? false)
                      TextButton(
                        onPressed: _openLocationSettings,
                        child: const Text('Pengaturan'),
                      ),
                  ],
                ),
              ),
            SizedBox(
              height: 220,
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _center,
                      initialZoom: 13,
                      onMapReady: () {
                        _mapReady = true;
                        _mapController.move(_center, 13);
                      },
                      onMapEvent: (event) {
                        // Geseran pengguna (bukan gerakan dari controller)
                        // menjeda mode ikuti selama navigasi. Peta tidak
                        // pernah dirotasi — utara selalu di atas.
                        if (_navigating &&
                            _followUser &&
                            event.source != MapEventSource.mapController) {
                          setState(() => _followUser = false);
                        }
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        // WAJIB: identifikasi aplikasi ke tile server OSM
                        // (tanpa ini request bisa diblokir).
                        userAgentPackageName: 'com.worthbang.worthbang',
                        maxNativeZoom: 19,
                      ),
                      if (_navigating && _routePoints.length >= 2)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _routePoints,
                              strokeWidth: 5,
                              color: const Color(0xFF1976D2),
                              borderStrokeWidth: 1.5,
                              borderColor: Colors.white,
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          if (_navigating)
                            Marker(
                              point: _displayPosition,
                              width: 48,
                              height: 48,
                              child: _NavUserMarker(headingDeg: _headingDeg),
                            )
                          else
                            Marker(
                              point: _center,
                              width: 40,
                              height: 40,
                              child: const Icon(
                                Icons.my_location,
                                color: Colors.blue,
                                size: 32,
                              ),
                            ),
                          for (final s in filteredStores)
                            Marker(
                              point: LatLng(s.lat, s.lng),
                              width: 40,
                              height: 40,
                              child: GestureDetector(
                                onTap: () => _selectStore(s),
                                child: const Icon(
                                  Icons.location_on,
                                  color: Colors.red,
                                  size: 32,
                                ),
                              ),
                            ),
                        ],
                      ),
                      // Wajib lisensi OSM: tampilkan atribusi kontributor.
                      RichAttributionWidget(
                        attributions: [
                          TextSourceAttribution('OpenStreetMap contributors'),
                        ],
                      ),
                    ],
                  ),
                  if (_navigating && !_followUser)
                    Positioned(
                      left: 12,
                      bottom: 12,
                      child: FilledButton.icon(
                        onPressed: () {
                          setState(() => _followUser = true);
                          if (_mapReady) {
                            _mapController.move(_displayPosition, _navZoom);
                          }
                        },
                        icon: const Icon(Icons.my_location, size: 18),
                        label: const Text(AppStrings.followAgainButton),
                      ),
                    ),
                  if (!_navigating)
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: FloatingActionButton.small(
                        heroTag: 'stores-current-location',
                        tooltip: 'Ke lokasi saya',
                        onPressed: _isLocating ? null : _locateAndLoad,
                        child: _isLocating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.my_location),
                      ),
                    ),
                ],
              ),
            ),
            if (_navigating && _selectedStore != null)
              _buildNavPanel(context, _selectedStore!)
            else if (_selectedStore != null)
              _buildStoreCard(context, _selectedStore!),
            Expanded(
              child: switch (state) {
                ApiLoading() => const Center(
                  child: MonexOrbitLoader(size: 56),
                ),
                ApiError<List<Store>> e => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      e.message,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
                _ =>
                  filteredStores.isEmpty
                      ? MonexEmptyState(
                          icon: Icons.store_mall_directory_outlined,
                          title: q.isEmpty
                              ? AppStrings.storesEmpty
                              : 'Tidak ada toko yang cocok dengan "$q".',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(
                              MonexSpacing.screenPaddingH),
                          itemCount: filteredStores.length,
                          itemBuilder: (context, i) {
                            final s = filteredStores[i];
                            return Padding(
                              padding: const EdgeInsets.only(
                                  bottom: MonexSpacing.gridGap),
                              child: MonexSurfaceCard(
                                padding: const EdgeInsets.all(
                                    MonexSpacing.cardPaddingCompact),
                                radius: MonexSpacing.radiusMd,
                                child: MonexTransactionTile(
                                  leadingIcon: Icons.storefront_outlined,
                                  title: s.name,
                                  titleStyle:
                                      Theme.of(context).textTheme.titleSmall,
                                  subtitle:
                                      '${s.address}\n${s.distanceKm.toStringAsFixed(1)} km',
                                  padding: EdgeInsets.zero,
                                  onTap: () => _selectStore(s),
                                ),
                              ),
                            );
                          },
                        ),
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Kartu detail toko terpilih: nama, alamat, jarak lurus saat ini,
  /// tombol mulai navigasi, tombol tutup untuk batal pilih.
  Widget _buildStoreCard(BuildContext context, Store store) {
    final theme = Theme.of(context);
    final straightMeters = const Distance()
        .as(LengthUnit.Meter, _center, LatLng(store.lat, store.lng))
        .toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
      child: MonexSurfaceCard(
        padding: const EdgeInsets.all(MonexSpacing.cardPaddingCompact),
        radius: MonexSpacing.radiusMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(store.name, style: theme.textTheme.titleSmall),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: AppStrings.cancelButton,
                  onPressed: () => setState(() => _selectedStore = null),
                ),
              ],
            ),
            Text(store.address, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              '${AppStrings.straightDistanceLabel}: '
              '${_formatDistance(straightMeters)}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            MonexPrimaryButton(
              label: _calculatingRoute
                  ? AppStrings.calculatingRoute
                  : AppStrings.navigateToStoreButton,
              icon: Icons.navigation_rounded,
              loading: _calculatingRoute,
              onPressed: _calculatingRoute ? null : _startNavigation,
            ),
          ],
        ),
      ),
    );
  }

  /// Panel selama navigasi: tujuan, sisa jarak + estimasi waktu yang
  /// hidup, status garis penunjuk/ketibaan, tombol akhiri.
  Widget _buildNavPanel(BuildContext context, Store store) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
      child: MonexSurfaceCard(
        padding: const EdgeInsets.all(MonexSpacing.cardPaddingCompact),
        radius: MonexSpacing.radiusMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.navigation_rounded,
                    size: 18, color: Color(0xFF1976D2)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(store.name, style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (_arrived)
              Text(
                '${AppStrings.arrivedAtPrefix} ${store.name}',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              )
            else
              Text(
                '${AppStrings.remainingDistanceLabel}: '
                '${_formatDistance(_remainingMeters)}'
                '  •  '
                '${AppStrings.etaLabel}: ${_formatDuration(_etaSeconds)}',
                style: theme.textTheme.bodyMedium,
              ),
            if (_routeIsFallback) ...[
              const SizedBox(height: 4),
              Text(
                AppStrings.routeFallbackToast,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 10),
            MonexSecondaryButton(
              label: AppStrings.endNavigationButton,
              icon: Icons.stop_circle_outlined,
              onPressed: _stopNavigation,
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  final km = (meters / 1000).toStringAsFixed(1).replaceAll('.', ',');
  return '$km km';
}

String _formatDuration(double seconds) {
  final minutes = (seconds / 60).round();
  if (minutes < 60) return '$minutes mnt';
  return '${minutes ~/ 60} j ${minutes % 60} mnt';
}

/// Marker pengguna selama navigasi: lingkaran biru dengan penunjuk
/// arah hadap (heading GPS) bila tersedia.
class _NavUserMarker extends StatelessWidget {
  const _NavUserMarker({this.headingDeg});

  final double? headingDeg;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF1976D2);
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: blue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 4),
            ],
          ),
        ),
        if (headingDeg != null)
          Transform.rotate(
            angle: headingDeg! * math.pi / 180,
            child: const Align(
              alignment: Alignment.topCenter,
              child: Icon(Icons.navigation_rounded, size: 15, color: blue),
            ),
          ),
      ],
    );
  }
}
