import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:worthbang/services/core/notification_service.dart';
import 'package:worthbang/services/features/price_check_api.dart';
import 'package:worthbang/screens/price_check_screen.dart'
    show priceCheckApiProvider;
import 'alerts_api.dart';

/// Notifier produksi (notifikasi lokal) — di-override fake di test.
final priceAlertNotifierProvider =
    Provider<PriceAlertNotifier>((ref) => LocalNotificationAlertNotifier());

/// Provider service cek alert (async karena butuh SharedPreferences).
final alertCheckServiceProvider =
    FutureProvider<AlertCheckService>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return AlertCheckService(
    alertsApi: ref.watch(alertsApiProvider),
    priceCheckApi: ref.watch(priceCheckApiProvider),
    notifier: ref.watch(priceAlertNotifierProvider),
    dedup: SharedPrefsDedupStore(prefs),
  );
});

/// Abstraksi notifikasi agar logika cek bisa di-unit-test.
abstract class PriceAlertNotifier {
  Future<void> showPriceAlert({
    required int id,
    required String query,
    required int currentPrice,
    required int targetPrice,
  });
}

class LocalNotificationAlertNotifier implements PriceAlertNotifier {
  @override
  Future<void> showPriceAlert({
    required int id,
    required String query,
    required int currentPrice,
    required int targetPrice,
  }) =>
      NotificationService.instance.showPriceAlert(
        id: id,
        query: query,
        currentPrice: currentPrice,
        targetPrice: targetPrice,
      );
}

/// Dedup: satu alert hanya notif sekali per level harga.
/// Direset saat harga kembali di atas target.
abstract class AlertDedupStore {
  Future<bool> wasNotified(int alertId, int price);
  Future<void> markNotified(int alertId, int price);
  Future<void> clear(int alertId);
}

class SharedPrefsDedupStore implements AlertDedupStore {
  SharedPrefsDedupStore(this._prefs);
  final SharedPreferences _prefs;

  static String _key(int alertId) => 'alert_notified_$alertId';

  @override
  Future<bool> wasNotified(int alertId, int price) async =>
      _prefs.getInt(_key(alertId)) == price;

  @override
  Future<void> markNotified(int alertId, int price) async =>
      _prefs.setInt(_key(alertId), price);

  @override
  Future<void> clear(int alertId) async =>
      _prefs.remove(_key(alertId));
}

/// Cek semua alert aktif: bandingkan harga pasar terkini vs target.
/// Dipakai worker 15 menit (background) dan tombol "cek sekarang".
class AlertCheckService {
  AlertCheckService({
    required this.alertsApi,
    required this.priceCheckApi,
    required this.notifier,
    required this.dedup,
  });

  final AlertsApi alertsApi;
  final PriceCheckApi priceCheckApi;
  final PriceAlertNotifier notifier;
  final AlertDedupStore dedup;

  /// Mengembalikan jumlah alert yang memicu notifikasi.
  Future<int> checkNow() async {
    final alerts =
        (await alertsApi.getAlerts()).where((a) => a.isActive);
    var triggered = 0;
    for (final alert in alerts) {
      try {
        final result = await priceCheckApi.analyze(
          mode: alert.mode,
          query: alert.query,
          price: alert.targetPrice,
        );
        final current =
            result.referencePrice ?? result.inputPrice;
        if (current <= alert.targetPrice) {
          if (!await dedup.wasNotified(alert.id, current)) {
            await notifier.showPriceAlert(
              id: alert.id,
              query: alert.query,
              currentPrice: current,
              targetPrice: alert.targetPrice,
            );
            await dedup.markNotified(alert.id, current);
            triggered++;
          }
        } else {
          // Harga naik lagi di atas target → boleh notif ulang nanti.
          await dedup.clear(alert.id);
        }
      } catch (_) {
        // Satu alert gagal (mis. offline) tidak menggagalkan yang lain.
      }
    }
    return triggered;
  }
}
