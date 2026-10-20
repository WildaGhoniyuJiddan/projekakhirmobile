import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show LazyDatabase;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'package:worthbang/services/alert_check_service.dart';
import 'package:worthbang/services/alerts_api.dart';
import 'package:worthbang/services/price_check_api.dart';
import 'package:worthbang/services/supabase_bootstrap.dart';
import 'package:worthbang/services/app_database.dart';

/// Nama task & tag untuk pengecekan price alert berkala.
const String priceAlertTaskName = 'worthbang.priceAlertCheck';

/// Entry point background — wajib top-level & annotated agar bisa
/// dipanggil isolate background WorkManager.
@pragma('vm:entry-point')
void workmanagerCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case priceAlertTaskName:
        AppDatabase? db;
        try {
          // Rakit dependensi manual (tanpa Riverpod — isolate terpisah).
          // Supabase perlu di-init di isolate ini agar engine bisa
          // mengambil listing pembanding.
          await initSupabase();
          final database = AppDatabase(
            LazyDatabase(() async {
              final dir = await getApplicationDocumentsDirectory();
              final file = File(p.join(dir.path, 'worthbang.sqlite'));
              return NativeDatabase.createInBackground(file);
            }),
          );
          db = database;
          final prefs = await SharedPreferences.getInstance();
          final service = AlertCheckService(
            alertsApi: AlertsApi(database),
            priceCheckApi: PriceCheckApi(),
            notifier: LocalNotificationAlertNotifier(),
            dedup: SharedPrefsDedupStore(prefs),
          );
          final n = await service.checkNow();
          debugPrint('WorthBang: price alert check selesai, $n terpicu.');
          return true;
        } catch (e) {
          debugPrint('WorthBang: price alert check gagal: $e');
          return false;
        } finally {
          await db?.close();
        }
    }
    return true;
  });
}

/// Inisialisasi WorkManager: cek price alert tiap 15 menit.
///
/// Dipanggil sekali dari [main]. Tidak dipanggil di widget test
/// (butuh platform channel asli).
Future<void> initWorkManager() async {
  await Workmanager().initialize(workmanagerCallbackDispatcher);
  await Workmanager().registerPeriodicTask(
    'worthbang-price-alert-periodic',
    priceAlertTaskName,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
  );
}

/// Fallback foreground: cek tiap 15 menit selagi app terbuka.
/// Dipakai bersama WorkManager (dedup mencegah notif ganda).
Timer startForegroundAlertChecker({
  required AlertCheckService service,
  Duration interval = const Duration(minutes: 15),
}) {
  return Timer.periodic(interval, (_) async {
    try {
      await service.checkNow();
    } catch (e) {
      debugPrint('WorthBang: foreground alert check gagal: $e');
    }
  });
}
