import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sync_queue.dart';

/// Sinkronisasi ulang antrean offline (T15).
///
/// Wishlist, alert, dan feedback sekarang 100% lokal sehingga tidak ada
/// lagi mutasi yang perlu dikirim ke server. Fungsi ini hanya menguras
/// sisa antrean lawas (best effort) agar tidak menumpuk.
class SyncService {
  SyncService({required this.queue});

  final SyncQueue queue;

  static const lastSyncKey = 'sync_last_at';

  /// Kuras antrean: item lawas dianggap selesai (datanya sudah lokal).
  /// Mengembalikan sisa antrian.
  Future<int> syncPending() async {
    final items = await queue.pending();
    for (final m in items) {
      await queue.remove(m.id);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
        lastSyncKey, DateTime.now().millisecondsSinceEpoch);
    return 0;
  }
}

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(queue: ref.watch(syncQueueProvider));
});

/// Waktu sinkron terakhir yang sukses (ms epoch) — untuk "Terakhir
/// diperbarui" di Riwayat.
final lastSyncAtProvider = FutureProvider<DateTime?>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final ms = prefs.getInt(SyncService.lastSyncKey);
  return ms == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(ms);
});
