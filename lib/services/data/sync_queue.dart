import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthbang/providers/providers.dart';
import 'package:worthbang/services/data/app_database.dart';

/// Antrian mutasi offline (T15): aksi yang gagal karena jaringan,
/// disimpan di SQLite dan dikirim ulang saat online.
class SyncQueue {
  SyncQueue(this._db);

  final AppDatabase _db;

  Future<void> enqueue(
      String kind, Map<String, dynamic> payload) async {
    await _db.into(_db.pendingMutations).insert(
          PendingMutationsCompanion.insert(
            kind: kind,
            payload: jsonEncode(payload),
          ),
        );
  }

  Future<List<PendingMutation>> pending() =>
      (_db.select(_db.pendingMutations)
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get();

  Future<void> remove(int id) =>
      (_db.delete(_db.pendingMutations)..where((t) => t.id.equals(id)))
          .go();

  Future<int> count() async {
    final row = await _db.customSelect(
      'SELECT COUNT(*) AS c FROM pending_mutations',
      readsFrom: {_db.pendingMutations},
    ).getSingle();
    return row.read<int>('c');
  }
}

final syncQueueProvider =
    Provider<SyncQueue>((ref) => SyncQueue(ref.watch(databaseProvider)));

/// Jumlah mutasi yang menunggu sinkron (untuk badge di Profil).
final pendingCountProvider = FutureProvider<int>((ref) async {
  // Ikuti perubahan manual via invalidate.
  return ref.watch(syncQueueProvider).count();
});
