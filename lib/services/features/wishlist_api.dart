import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthbang/providers/providers.dart';
import 'package:worthbang/services/data/app_database.dart' as db;

final wishlistApiProvider = Provider<WishlistApi>(
  (ref) => WishlistApi(ref.watch(databaseProvider)),
);

/// Item wishlist (sekarang 100% lokal — tabel Drift WishlistItems).
class WishlistItem {
  const WishlistItem({
    required this.id,
    required this.query,
    required this.mode,
    this.targetPrice,
    this.createdAt,
  });

  final int id;
  final String query;
  final String mode;
  final int? targetPrice;
  final DateTime? createdAt;

  factory WishlistItem.fromDb(db.WishlistItem row) => WishlistItem(
        id: row.id,
        query: row.query,
        mode: row.mode,
        targetPrice: row.targetPrice,
        createdAt: row.createdAt,
      );

  factory WishlistItem.fromJson(Map<String, dynamic> json) {
    DateTime? created;
    final c = json['created_at'] as String?;
    if (c != null) created = DateTime.tryParse(c);
    return WishlistItem(
      id: (json['id'] as num).toInt(),
      query: json['query'] as String? ?? '',
      mode: json['mode'] as String? ?? 'pc',
      targetPrice: (json['target_price'] as num?)?.toInt(),
      createdAt: created,
    );
  }
}

class WishlistApi {
  WishlistApi(this._db);

  final db.AppDatabase _db;

  Future<List<WishlistItem>> getWishlist() async {
    final rows = await (_db.select(_db.wishlistItems)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
    return rows.map(WishlistItem.fromDb).toList();
  }

  Future<WishlistItem> addWishlist({
    required String query,
    required String mode,
    int? targetPrice,
  }) async {
    final id = await _db.into(_db.wishlistItems).insert(
          db.WishlistItemsCompanion.insert(
            query: query,
            mode: mode,
            targetPrice: Value(targetPrice),
          ),
        );
    final row = await (_db.select(_db.wishlistItems)
          ..where((t) => t.id.equals(id)))
        .getSingle();
    return WishlistItem.fromDb(row);
  }

  Future<void> deleteWishlist(int id) =>
      (_db.delete(_db.wishlistItems)..where((t) => t.id.equals(id))).go();
}
