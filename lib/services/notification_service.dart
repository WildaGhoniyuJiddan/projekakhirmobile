import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notifikasi lokal: price alert (dedup ditangani [AlertCheckService]).
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channelId = 'worthbang_price_alerts';
  static const _channelName = 'Price Alert';

  /// Inisialisasi sekali dari [main]. Aman dipanggil ulang.
  Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings: settings);
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'Notifikasi saat harga menyentuh target',
          importance: Importance.high,
        ));
    _ready = true;
  }

  /// Tampilkan notifikasi price alert. [id] = id alert (unik per alert).
  Future<void> showPriceAlert({
    required int id,
    required String query,
    required int currentPrice,
    required int targetPrice,
  }) async {
    if (!_ready) await init();
    await _plugin.show(
      id: id,
      title: 'Harga $query turun!',
      body:
          'Rp $currentPrice ≤ target Rp $targetPrice — cek sekarang.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}
