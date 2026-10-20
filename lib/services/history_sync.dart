import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:worthbang/services/app_database.dart';

/// Sinkronisasi riwayat analisis ke Supabase — pengganti jalur
/// `/api/v1/history` backend Python (B10).
///
/// Baris ditulis ke tabel `analysis_logs` dengan `user_uuid` =
/// auth.uid() user yang sedang login; RLS memastikan tiap user
/// hanya bisa membaca/menulis baris miliknya.
class HistorySync {
  HistorySync([SupabaseClient? client]) : _injectedClient = client;

  final SupabaseClient? _injectedClient;

  /// Diambil malas: konstruksi service tidak meledak sebelum
  /// `initSupabase()` jalan (error muncul di pemakaian, ter-tangkap
  /// sebagai sync gagal = best effort).
  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  String? get _uid => _client.auth.currentUser?.id;

  /// Insert [blocks] (urut id menaik) ke `analysis_logs`.
  ///
  /// Semantik B10 dipertahankan: `created_at` di masa depan di-clamp
  /// ke sekarang; waktu dikirim sebagai UTC. Berhenti pada kegagalan
  /// pertama (offline) — sisanya tetap antre di lokal.
  /// Mengembalikan jumlah blok yang berhasil terkirim.
  Future<int> pushBlocks(List<HistoryBlock> blocks) async {
    final uid = _uid;
    if (uid == null) return 0;
    final now = DateTime.now().toUtc();
    var sent = 0;
    for (final b in blocks) {
      var createdAt = b.createdAt.toUtc();
      if (createdAt.isAfter(now)) createdAt = now;
      try {
        await _client.from('analysis_logs').insert({
          'mode': b.mode,
          'input_query': b.query,
          'input_price': b.inputPrice,
          'result_score': b.score,
          'verdict': b.verdict,
          'user_uuid': uid,
          'created_at': createdAt.toIso8601String(),
        });
        sent++;
      } catch (_) {
        break;
      }
    }
    return sent;
  }

  /// Ambil riwayat server milik user login (pengganti GET
  /// `/api/v1/history`), terbaru dulu. Kosong bila belum login.
  Future<List<Map<String, dynamic>>> fetchMine({int limit = 100}) async {
    final uid = _uid;
    if (uid == null) return const [];
    final rows = await _client
        .from('analysis_logs')
        .select()
        .eq('user_uuid', uid)
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }
}
