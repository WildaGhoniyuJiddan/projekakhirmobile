import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Dataset JSON lokal (mirror file di backend/app/data/ repo lama):
/// benchmark_scores.json, consensus_scores.json, new_price_reference.json,
/// retail_catalog.json. Di Dart dataset dimuat dari asset, bukan file path.
class BenchmarkData {
  const BenchmarkData({
    required this.bench,
    required this.consensus,
    required this.newPriceRef,
    required this.retail,
  });

  /// benchmark_scores.json — {generated_at, cpu, cpu_mobile, gpu}.
  final Map<String, dynamic> bench;

  /// consensus_scores.json — {cpu, gpu, generated_at, method}.
  final Map<String, dynamic> consensus;

  /// new_price_reference.json — {gpu, cpu, retail_idr}.
  final Map<String, dynamic> newPriceRef;

  /// retail_catalog.json — {gpu, cpu, motherboard, ram, storage,
  /// ram_canonical, storage_canonical, ...} (list per section).
  final Map<String, dynamic> retail;

  /// Instance terakhir hasil [load] — dipakai seam fungsi top-level
  /// (benchmark_api.dart) dan glue aplikasi. Mirror dataset global Python.
  static BenchmarkData? instance;

  static Map<String, dynamic> _decode(Object? raw) {
    if (raw is Map) return raw.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  factory BenchmarkData.fromMaps({
    Map<String, dynamic>? bench,
    Map<String, dynamic>? consensus,
    Map<String, dynamic>? newPriceRef,
    Map<String, dynamic>? retail,
  }) =>
      BenchmarkData(
        bench: bench ?? <String, dynamic>{},
        consensus: consensus ?? <String, dynamic>{},
        newPriceRef: newPriceRef ?? <String, dynamic>{},
        retail: retail ?? <String, dynamic>{},
      );

  static Future<BenchmarkData> load() async {
    Future<Map<String, dynamic>> read(String name) async {
      try {
        final text = await rootBundle.loadString('assets/data/$name');
        return _decode(jsonDecode(text));
      } catch (_) {
        // Mirror perilaku Python: file gagal dibaca -> katalog kosong.
        return <String, dynamic>{};
      }
    }

    final data = BenchmarkData(
      bench: await read('benchmark_scores.json'),
      consensus: await read('consensus_scores.json'),
      newPriceRef: await read('new_price_reference.json'),
      retail: await read('retail_catalog.json'),
    );
    instance = data;
    return data;
  }

  /// Sub-katalog benchmark per tipe ("cpu" / "cpu_mobile" / "gpu").
  Map<String, dynamic> benchCatalog(String type) =>
      _decode(bench[type]);

  /// Sub-katalog konsensus per tipe ("cpu" / "gpu").
  Map<String, dynamic> consensusCatalog(String type) =>
      _decode(consensus[type]);
}

/// Satu baris listing pasar (mirror kolom raw_listings yang dipakai
/// analysis.py) + unit laptop/komponen untuk mode laptop.
class ListingRow {
  const ListingRow({
    required this.title,
    required this.price,
    this.source,
    this.condition,
    this.url,
    this.specText,
    this.category,
    this.scrapedAt,
  });

  final String title;
  final int price;
  final String? source;
  final String? condition;
  final String? url;
  final String? specText;
  final String? category;
  final DateTime? scrapedAt;
}

/// Sumber data listing — diimplementasikan koordinator di atas Supabase
/// (RPC match_listings / PostgREST). Mesin analisis hanya tahu seam ini.
abstract class ListingsSource {
  Future<List<ListingRow>> pcListings({
    String? modelNum,
    required List<String> categories,
  });

  /// Baris laptop_units sebagai map kolom snake_case:
  /// brand, model, cpu, gpu, ram_gb, storage_gb, price, condition,
  /// source, listing_url, scraped_at (DateTime atau ISO string).
  Future<List<Map<String, Object?>>> laptopUnits({
    required List<String> tokens,
  });

  /// Baris pc_components sebagai map kolom snake_case:
  /// component_type, brand, model, sample_count, avg_price.
  Future<List<Map<String, Object?>>> pcComponents({
    required List<String> tokens,
  });

  Future<DateTime?> latestScrapedAt();
}
