import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../config/supabase_config.dart';

/// Produk ternormalisasi untuk etalase menu Cari (satu baris per
/// produk, nama bersih — mis. "Colorful RTX 3050 6GB").
class NormalizedProduct {
  const NormalizedProduct({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    this.imageUrl,
  });

  final String id;
  final String name;

  /// Kunci seksi katalog ('gpu', 'cpu', 'motherboard', 'ram',
  /// 'storage', 'laptop', 'pc').
  final String category;
  final int price;

  /// URL gambar publik (Supabase Storage) bila manifest menyatakan
  /// status 'ok'; selain itu null -> UI menampilkan placeholder ikon.
  final String? imageUrl;
}

/// Loader dataset produk ternormalisasi bundled
/// (assets/data/products_normalized.json, dibuat pipeline Rev-Data)
/// digabung manifest gambar (assets/data/products_images_manifest.json).
///
/// Defensif: aset belum ada / JSON rusak -> daftar kosong, pemanggil
/// menyembunyikan etalase dengan anggun.
class ProductsCatalog {
  ProductsCatalog._();

  static List<NormalizedProduct>? _cache;

  static Future<List<NormalizedProduct>> load() async {
    final cached = _cache;
    if (cached != null) return cached;
    final out = await _loadFresh();
    _cache = out;
    return out;
  }

  static Future<List<NormalizedProduct>> _loadFresh() async {
    try {
      final raw = await rootBundle.loadString(
        'assets/data/products_normalized.json',
      );
      final decoded = jsonDecode(raw);
      final List<dynamic> list;
      if (decoded is Map<String, dynamic>) {
        list = decoded['products'] as List<dynamic>? ?? const [];
      } else if (decoded is List<dynamic>) {
        list = decoded;
      } else {
        return const [];
      }
      final manifest = await _loadManifest();
      return [
        for (final e in list)
          if (e is Map<String, dynamic>)
            NormalizedProduct(
              id: e['id'] as String? ?? '',
              name: e['name'] as String? ?? '-',
              category: e['category'] as String? ?? '',
              price: (e['price'] as num?)?.toInt() ?? 0,
              imageUrl: _imageUrl(e['id'] as String?, manifest),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<Map<String, dynamic>> _loadManifest() async {
    try {
      final raw = await rootBundle.loadString(
        'assets/data/products_images_manifest.json',
      );
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }

  /// Hanya entri manifest berstatus 'ok' yang punya URL gambar;
  /// fallback (chipset/kategori) dan entri hilang -> null.
  static String? _imageUrl(String? id, Map<String, dynamic> manifest) {
    if (id == null || id.isEmpty) return null;
    final entry = manifest[id];
    if (entry is! Map<String, dynamic>) return null;
    if (entry['status'] != 'ok') return null;
    final file = entry['file'] as String?;
    if (file == null || file.isEmpty) return null;
    return '$supabaseUrl/storage/v1/object/public/product-images/$file';
  }
}
