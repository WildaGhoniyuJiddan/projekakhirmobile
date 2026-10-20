import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthbang/providers/providers.dart';
import 'package:worthbang/services/app_database.dart' as db;

final alertsApiProvider = Provider<AlertsApi>(
  (ref) => AlertsApi(ref.watch(databaseProvider)),
);

/// Price alert (sekarang 100% lokal — tabel Drift PriceAlerts).
class PriceAlert {
  const PriceAlert({
    required this.id,
    required this.query,
    required this.targetPrice,
    this.mode = 'pc',
    this.currentPrice,
    this.isActive = true,
  });

  final int id;
  final String query;
  final int targetPrice;
  final String mode;
  final int? currentPrice;
  final bool isActive;

  factory PriceAlert.fromDb(db.PriceAlert row) => PriceAlert(
        id: row.id,
        query: row.query,
        targetPrice: row.targetPrice,
        mode: row.mode,
        isActive: row.isActive,
      );

  factory PriceAlert.fromJson(Map<String, dynamic> json) => PriceAlert(
        id: (json['id'] as num).toInt(),
        query: json['query'] as String? ?? '',
        targetPrice: (json['target_price'] as num).toInt(),
        mode: json['mode'] as String? ?? 'pc',
        currentPrice: (json['current_price'] as num?)?.toInt(),
        isActive: json['is_active'] as bool? ?? true,
      );
}

class AlertsApi {
  AlertsApi(this._db);

  final db.AppDatabase _db;

  Future<List<PriceAlert>> getAlerts() async {
    final rows = await (_db.select(_db.priceAlerts)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
    return rows.map(PriceAlert.fromDb).toList();
  }

  Future<PriceAlert> addAlert({
    required String query,
    required String mode,
    required int targetPrice,
    String condition = 'any',
  }) async {
    final id = await _db.into(_db.priceAlerts).insert(
          db.PriceAlertsCompanion.insert(
            query: query,
            mode: mode,
            targetPrice: targetPrice,
          ),
        );
    final row = await (_db.select(_db.priceAlerts)
          ..where((t) => t.id.equals(id)))
        .getSingle();
    return PriceAlert.fromDb(row);
  }

  Future<void> deleteAlert(int id) =>
      (_db.delete(_db.priceAlerts)..where((t) => t.id.equals(id))).go();
}
