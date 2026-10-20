import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:worthbang/services/api_result.dart';
import 'package:worthbang/core/theme/monex_theme.dart';
import 'package:worthbang/core/widgets/monex_widgets.dart';
import 'package:worthbang/l10n/strings.dart';
import 'package:worthbang/models/store_models.dart';
import 'package:worthbang/services/stores_api.dart';

/// Koordinat fallback (demo Jakarta) bila izin lokasi ditolak / gagal.
const _demoLat = -6.2088;
const _demoLng = 106.8456;

/// Layar Toko Terdekat: peta + daftar termurah untuk produk yang dicari.
class StoresScreen extends ConsumerStatefulWidget {
  const StoresScreen({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  ConsumerState<StoresScreen> createState() => _StoresScreenState();
}

class _StoresScreenState extends ConsumerState<StoresScreen> {
  final _query = TextEditingController();
  final _mapController = MapController();
  ApiResult<List<Store>>? _state;
  LatLng _center = const LatLng(_demoLat, _demoLng);
  bool _usingDemoLocation = true;
  bool _mapReady = false;
  bool _isLocating = false;
  String? _locationMessage;

  @override
  void initState() {
    super.initState();
    _query.text = widget.initialQuery;
    _locateAndLoad();
  }

  @override
  void dispose() {
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
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
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
                      MarkerLayer(
                        markers: [
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
                                onTap: () {
                                  _mapController.move(LatLng(s.lat, s.lng), 15);
                                  showMonexToast(
                                    context,
                                    '${s.name}\n${s.address}',
                                  );
                                },
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
                                  onTap: () {
                                    _mapController.move(
                                        LatLng(s.lat, s.lng), 15);
                                  },
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
}
