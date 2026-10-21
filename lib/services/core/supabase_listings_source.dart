import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../engine/dataset.dart';

/// Implementasi ListingsSource di atas Supabase (PostgREST + RPC).
///
/// - Listing PC: RPC match_listings (prefilter SQL mirror analysis.py).
/// - Unit laptop & komponen PC: PostgREST; mesin analisis memfilter
///   in-memory secara otoritatif, di sini cukup kandidat terbaru.
/// - Supabase belum init / query gagal -> hasil kosong (analyze jatuh
///   ke verdict "data terbatas", aplikasi tidak crash).
class SupabaseListingsSource implements ListingsSource {
  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<ListingRow>> pcListings({
    String? modelNum,
    required List<String> categories,
  }) async {
    final client = _client;
    if (client == null) return const [];
    try {
      final rows = await client.rpc(
        'match_listings',
        params: {
          'p_model_num':
              (modelNum == null || modelNum.isEmpty) ? null : modelNum,
          'p_categories': categories,
        },
      );
      return (rows as List)
          .whereType<Map<String, dynamic>>()
          .map(_rowFromJson)
          .toList();
    } catch (e) {
      debugPrint('SupabaseListingsSource.pcListings gagal: $e');
      return const [];
    }
  }

  @override
  Future<List<Map<String, Object?>>> laptopUnits({
    required List<String> tokens,
  }) async {
    final client = _client;
    if (client == null) return const [];
    try {
      final rows = await client
          .from('laptop_units')
          .select(
            'brand, model, cpu, gpu, ram_gb, storage_gb, screen_size, '
            'price, condition, source, listing_url, scraped_at',
          )
          .order('scraped_at', ascending: false)
          .limit(1500);
      return rows.map((r) => r.cast<String, Object?>()).toList();
    } catch (e) {
      debugPrint('SupabaseListingsSource.laptopUnits gagal: $e');
      return const [];
    }
  }

  @override
  Future<List<Map<String, Object?>>> pcComponents({
    required List<String> tokens,
  }) async {
    final client = _client;
    if (client == null) return const [];
    try {
      final rows = await client
          .from('pc_components')
          .select(
            'component_type, brand, model, benchmark_score, avg_price, '
            'sample_count',
          )
          .limit(1000);
      return rows.map((r) => r.cast<String, Object?>()).toList();
    } catch (e) {
      debugPrint('SupabaseListingsSource.pcComponents gagal: $e');
      return const [];
    }
  }

  @override
  Future<DateTime?> latestScrapedAt() async {
    final client = _client;
    if (client == null) return null;
    try {
      final rows = await client
          .from('raw_listings')
          .select('scraped_at')
          .order('scraped_at', ascending: false)
          .limit(1);
      if (rows.isEmpty) return null;
      return DateTime.tryParse(rows.first['scraped_at'] as String? ?? '');
    } catch (e) {
      debugPrint('SupabaseListingsSource.latestScrapedAt gagal: $e');
      return null;
    }
  }

  ListingRow _rowFromJson(Map<String, dynamic> j) => ListingRow(
        title: j['raw_title'] as String? ?? '',
        price: (j['raw_price'] as num? ?? 0).toInt(),
        source: j['source'] as String?,
        condition: j['condition'] as String?,
        url: j['listing_url'] as String?,
        specText: j['raw_spec_text'] as String?,
        category: j['category'] as String?,
        scrapedAt: DateTime.tryParse(j['scraped_at'] as String? ?? ''),
      );
}
