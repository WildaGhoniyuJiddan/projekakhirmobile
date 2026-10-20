import 'package:drift/drift.dart';

import 'package:worthbang/services/hash_chain_service.dart';
import 'package:worthbang/services/app_database.dart';
import 'package:worthbang/services/history_sync.dart';
import 'package:worthbang/models/price_check_models.dart';

/// Repository riwayat: simpan hasil analisis sebagai blok hash chain (Drift).
class HistoryRepository {
  HistoryRepository(this._db, [HistorySync? sync]) : _sync = sync;

  final AppDatabase _db;
  final HistorySync? _sync;

  /// Simpan [result] sebagai blok baru di ujung rantai.
  ///
  /// Hash dihitung setelah insert agar `id` (auto-increment) bisa dipakai
  /// sebagai index sesuai format D12.
  Future<HistoryBlock> appendAnalysis(AnalysisResult result) async {
    // Drift menyimpan DateTime sebagai unix seconds dan membacanya sebagai
    // LOCAL time — truncate ke detik & pakai local agar string ISO yang
    // di-hash identik dengan yang dibaca saat verifikasi.
    final now = DateTime.now();
    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      (now.millisecondsSinceEpoch ~/ 1000) * 1000,
    );
    final dataJson = HashChainService.canonicalDataJson(
      mode: result.mode,
      query: result.query,
      inputPrice: result.inputPrice,
      score: result.score,
      verdict: result.verdict,
    );

    return _db.transaction(() async {
      final id = await _db.into(_db.historyBlocks).insert(
            HistoryBlocksCompanion.insert(
              mode: result.mode,
              query: result.query,
              inputPrice: result.inputPrice,
              score: result.score,
              verdict: result.verdict,
              createdAt: Value(createdAt),
            ),
          );
      // Blok sebelumnya = id terbesar yang LEBIH KECIL dari id baru
      // (baris baru sendiri hash-nya masih kosong).
      final prev = await (_db.select(_db.historyBlocks)
            ..where((t) => t.id.isSmallerThanValue(id))
            ..orderBy([(t) => OrderingTerm.desc(t.id)])
            ..limit(1))
          .getSingleOrNull();
      final prevHash = (prev == null || prev.hash.isEmpty)
          ? HashChainService.genesisPrevHash
          : prev.hash;
      final hash = HashChainService.computeHash(
        index: id,
        timestampIso: createdAt.toIso8601String(),
        dataJson: dataJson,
        prevHash: prevHash,
      );
      await (_db.update(_db.historyBlocks)..where((t) => t.id.equals(id)))
          .write(HistoryBlocksCompanion(
        dataJson: Value(dataJson),
        prevHash: Value(prevHash),
        hash: Value(hash),
      ));
      return (await (_db.select(_db.historyBlocks)
                ..where((t) => t.id.equals(id)))
              .getSingle());
    });
  }

  /// Daftar blok terbaru dulu (untuk layar Riwayat).
  Future<List<HistoryBlock>> latest({int limit = 100}) =>
      (_db.select(_db.historyBlocks)
            ..orderBy([(t) => OrderingTerm.desc(t.id)])
            ..limit(limit))
          .get();

  /// Verifikasi seluruh rantai (urut id menaik).
  Future<List<HashVerificationResult>> verify() async {
    final blocks = await (_db.select(_db.historyBlocks)
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    return HashChainService.verifyChain(
      blocks
          .map((b) => HashBlock(
                id: b.id,
                timestampIso: b.createdAt.toIso8601String(),
                dataJson: b.dataJson,
                prevHash: b.prevHash,
                hash: b.hash,
              ))
          .toList(),
    );
  }

  /// Hapus satu blok (demo; merusak rantai — untuk self-test T6).
  Future<void> deleteBlock(int id) =>
      (_db.delete(_db.historyBlocks)..where((t) => t.id.equals(id))).go();

  /// Sync opsional ke Supabase (B10, dulu POST /api/v1/history) —
  /// best effort via [HistorySync]. Mengembalikan jumlah blok yang
  /// berhasil terkirim. Rantai hash lokal tidak berubah.
  Future<int> syncToServer() async {
    final blocks = await (_db.select(_db.historyBlocks)
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    return (_sync ?? HistorySync()).pushBlocks(blocks);
  }

}
