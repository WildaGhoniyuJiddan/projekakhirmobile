import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_catalog.dart';

import 'package:worthbang/models/trend_models.dart';

final trendsApiProvider = Provider<TrendsApi>((ref) => TrendsApi());

/// Tren harga — sekarang 100% lokal dari katalog bundled.
///
/// Jujur soal data: dataset sekali-pakai ini tidak punya riwayat harga
/// per tanggal, jadi tidak ada grafik time-series (points kosong).
/// Yang ditampilkan adalah statistik nyata dari katalog:
/// harga termurah, termahal, dan rata-rata untuk query tersebut.
class TrendsApi {
  Future<TrendData> getTrend(String query, {int days = 30}) async {
    final items = await LocalCatalog.allItems();
    final tokens = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 1)
        .toList();

    final matched = items.where((e) {
      final m = e.model.toLowerCase();
      return tokens.isNotEmpty &&
          tokens.every((t) => m.contains(t)) &&
          e.price > 0;
    }).toList();

    if (matched.isEmpty) {
      return TrendData(
        query: query,
        days: days,
        points: const [],
        min: 0,
        max: 0,
        avg: 0,
        changePercent: 0,
        summary: 'Tidak ada item "$query" di katalog saat ini.',
      );
    }

    final prices = matched.map((e) => e.price).toList()..sort();
    final min = prices.first;
    final max = prices.last;
    final avg = prices.reduce((a, b) => a + b) / prices.length;

    return TrendData(
      query: query,
      days: days,
      points: const [],
      min: min,
      max: max,
      avg: avg,
      changePercent: 0,
      summary:
          'Berdasarkan ${matched.length} item "$query" di katalog saat ini: '
          'termurah Rp$min, termahal Rp$max, rata-rata Rp${avg.round()}. '
          'Dataset ini sekali-pakai (tanpa riwayat per tanggal), '
          'jadi tidak ada grafik tren waktu.',
    );
  }
}
