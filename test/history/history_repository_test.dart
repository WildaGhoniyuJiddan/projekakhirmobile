import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthbang/services/data/app_database.dart';
import 'package:worthbang/services/data/history_repository.dart';
import 'package:worthbang/models/price_check_models.dart';

AnalysisResult _result(String query, int price) => AnalysisResult(
      mode: 'pc',
      query: query,
      inputPrice: price,
      score: 80.0,
      verdict: 'wajar',
    );

void main() {
  late AppDatabase db;
  late HistoryRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = HistoryRepository(db);
  });

  tearDown(() => db.close());

  group('HistoryRepository (Drift in-memory)', () {
    test('append 2 analisis → rantai valid', () async {
      await repo.appendAnalysis(_result('RTX 4060', 4500000));
      await repo.appendAnalysis(_result('Ryzen 5 5600', 1800000));

      final blocks = await repo.latest();
      expect(blocks.length, 2);
      expect(blocks.first.query, 'Ryzen 5 5600'); // terbaru dulu

      final results = await repo.verify();
      expect(results.length, 2);
      expect(results.every((r) => r.ok), isTrue);
    });

    test('blok pertama pakai prevHash GENESIS', () async {
      final block = await repo.appendAnalysis(_result('RTX 4060', 4500000));
      expect(block.prevHash, 'GENESIS');
      expect(block.hash, hasLength(64));
      expect(block.dataJson, contains('RTX 4060'));
    });

    test('blok kedua me-link ke hash blok pertama', () async {
      final b1 = await repo.appendAnalysis(_result('A', 1000));
      final b2 = await repo.appendAnalysis(_result('B', 2000));
      expect(b2.prevHash, b1.hash);
    });

    test('hapus blok tengah → verifikasi gagal', () async {
      final b1 = await repo.appendAnalysis(_result('A', 1000));
      await repo.appendAnalysis(_result('B', 2000));
      await repo.appendAnalysis(_result('C', 3000));
      await repo.deleteBlock(b1.id + 1); // hapus blok tengah

      final results = await repo.verify();
      expect(results.any((r) => !r.ok), isTrue);
    });
  });
}
