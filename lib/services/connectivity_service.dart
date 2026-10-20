import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stream status konektivitas perangkat.
final connectivityProvider =
    StreamProvider<List<ConnectivityResult>>((ref) {
  final connectivity = Connectivity();
  return connectivity.onConnectivityChanged;
});

/// true bila perangkat offline (semua interface none).
final isOfflineProvider = Provider<bool>((ref) {
  final results = ref.watch(connectivityProvider).value;
  // Sebelum status pertama diketahui, anggap online agar UI tidak
  // salah menampilkan banner.
  if (results == null) return false;
  return results.every((r) => r == ConnectivityResult.none);
});
