import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;

/// Item katalog retail (dari assets/data/retail_catalog.json).
/// Item tanpa field segment/tier (laptop/PC verbatim katalog lama)
/// dianggap consumer/primary agar perilaku lama tetap jalan.
class CatalogItem {
  const CatalogItem({
    required this.model,
    required this.price,
    this.segment = 'consumer',
    this.tier = 'primary',
  });

  final String model;
  final int price;
  final String segment;
  final String tier;

  /// Lolos filter konsumen: bukan komponen server dan bukan lapis
  /// cadangan (harga di atas batas wajar pasar).
  bool get isConsumer => segment != 'enterprise' && tier != 'fallback';
}

/// Loader katalog retail bundled — dipakai builder, game tebak harga,
/// dan tren lokal. Sekali load lalu di-cache di memori.
///
/// Sejak baseline komponen_pc.csv (2026-10-27), file aset membawa
/// field segment/tier: secara default [load] hanya mengembalikan item
/// konsumen lapis utama (segment != enterprise, tier != fallback)
/// supaya komponen server ratusan juta dan barang overpriced tidak
/// bocor ke Rakit PC / Kuis / Tren. Lewatkan [consumerOnly] = false
/// bila memang butuh seluruh isi katalog.
class LocalCatalog {
  LocalCatalog._();

  static Map<String, List<CatalogItem>>? _cache;

  static Future<Map<String, List<CatalogItem>>> load({
    bool consumerOnly = true,
  }) async {
    final cached = _cache;
    if (cached == null) {
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
                segment: e['segment'] as String? ?? 'consumer',
                tier: e['tier'] as String? ?? 'primary',
              ),
        ];
      }
      _cache = out;
      return _view(out, consumerOnly);
    }
    return _view(cached, consumerOnly);
  }

  static Map<String, List<CatalogItem>> _view(
    Map<String, List<CatalogItem>> full,
    bool consumerOnly,
  ) {
    if (!consumerOnly) {
      return {for (final e in full.entries) e.key: List.of(e.value)};
    }
    return {
      for (final e in full.entries)
        e.key: e.value.where((i) => i.isConsumer).toList(),
    };
  }

  /// Semua item dari semua seksi (gpu, cpu, motherboard, ...).
  static Future<List<CatalogItem>> allItems({
    bool consumerOnly = true,
  }) async {
    final cat = await load(consumerOnly: consumerOnly);
    return cat.values.expand((l) => l).toList();
  }

  /// Item acak dari seksi gpu/cpu (untuk game tebak harga).
  static Future<CatalogItem> randomGameItem(
    Random rng, {
    bool consumerOnly = true,
  }) async {
    final cat = await load(consumerOnly: consumerOnly);
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
