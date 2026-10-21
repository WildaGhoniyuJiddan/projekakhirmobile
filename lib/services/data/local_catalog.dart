import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;

/// Item katalog retail (dari assets/data/retail_catalog.json).
class CatalogItem {
  const CatalogItem({required this.model, required this.price});

  final String model;
  final int price;
}

/// Loader katalog retail bundled — dipakai builder, game tebak harga,
/// dan tren lokal. Sekali load lalu di-cache di memori.
class LocalCatalog {
  LocalCatalog._();

  static Map<String, List<CatalogItem>>? _cache;

  static Future<Map<String, List<CatalogItem>>> load() async {
    final cached = _cache;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString(
      'assets/data/retail_catalog.json',
    );
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final out = <String, List<CatalogItem>>{};
    for (final entry in decoded.entries) {
      final v = entry.value;
      if (v is! List) continue; // lewati 'generated_at'
      out[entry.key] = [
        for (final e in v)
          if (e is Map<String, dynamic>)
            CatalogItem(
              model: e['model'] as String? ?? '-',
              price: (e['price'] as num?)?.toInt() ?? 0,
            ),
      ];
    }
    _cache = out;
    return out;
  }

  /// Semua item dari semua seksi (gpu, cpu, motherboard, ...).
  static Future<List<CatalogItem>> allItems() async {
    final cat = await load();
    return cat.values.expand((l) => l).toList();
  }

  /// Item acak dari seksi gpu/cpu (untuk game tebak harga).
  static Future<CatalogItem> randomGameItem(Random rng) async {
    final cat = await load();
    final pool = [
      ...?cat['gpu'],
      ...?cat['cpu'],
    ].where((e) => e.price > 0).toList();
    if (pool.isEmpty) {
      throw StateError('Katalog kosong');
    }
    return pool[rng.nextInt(pool.length)];
  }
}
