import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:worthbang/utils/app.dart';
import 'package:worthbang/services/notification_service.dart';
import 'package:worthbang/services/supabase_bootstrap.dart';
import 'package:worthbang/services/work_manager.dart';

/// Entry point aplikasi WorthBang.
///
/// Semua teks user-facing berbahasa Indonesia (lihat [lib/l10n]).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Supabase (auth + history) — no-op bila config belum diisi.
  await initSupabase();
  // Default locale Indonesia untuk formatter intl (Rp, tanggal).
  Intl.defaultLocale = 'id_ID';
  await initializeDateFormatting('id_ID');
  // Background check price alert tiap 15 menit (T11: WorkManager).
  await initWorkManager();
  // Notifikasi lokal untuk price alert.
  await NotificationService.instance.init();
  runApp(const ProviderScope(child: WorthBangApp()));
}
