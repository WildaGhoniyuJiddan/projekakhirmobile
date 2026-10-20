import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:worthbang/config/supabase_config.dart';

/// Inisialisasi Supabase sekali di `main()` sebelum `runApp`.
///
/// Bila config masih placeholder (belum diisi Dan), fungsi ini no-op:
/// aplikasi tetap jalan, fitur yang butuh Supabase akan gagal di
/// pemanggilnya — bukan crash saat start.
Future<void> initSupabase() async {
  if (!supabaseConfigured) return;
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
}
