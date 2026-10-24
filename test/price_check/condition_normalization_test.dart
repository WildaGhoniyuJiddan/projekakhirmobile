/// Tes normalisasi kondisi — perbaikan bug kosakata ('baru'/'bekas' UI
/// vs 'new'/'second' DB). Sebelum fix, filter kondisi di _pcComparisons
/// membandingkan input mentah dengan nilai DB sehingga input 'bekas'
/// menghasilkan 0 pembanding dan analisis jatuh ke fallback ML/anchor.
///
/// Seam: AnalysisEngine langsung dengan BenchmarkData.fromMaps() kosong
/// (tanpa retail/anchor, tanpa model ML) + ListingsSource palsu, supaya
/// yang diuji murni logika kondisi engine, bukan data asset.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:worthbang/services/engine/analysis_engine.dart';
import 'package:worthbang/services/engine/dataset.dart';

class _FakeListings implements ListingsSource {
  _FakeListings(this.rows);

  final List<ListingRow> rows;

  @override
  Future<List<ListingRow>> pcListings({
    String? modelNum,
    required List<String> categories,
  }) async =>
      rows;

  @override
  Future<List<Map<String, Object?>>> laptopUnits({
    required List<String> tokens,
  }) async =>
      [];

  @override
  Future<List<Map<String, Object?>>> pcComponents({
    required List<String> tokens,
  }) async =>
      [];

  @override
  Future<DateTime?> latestScrapedAt() async => null;
}

ListingRow _row(String title, int price, String condition) => ListingRow(
      title: title,
      price: price,
      source: 'tokopedia',
      condition: condition,
    );

Future<AnalysisOutcome> _analyze(
  List<ListingRow> rows, {
  required String query,
  required int price,
  String? componentType,
  String condition = 'any',
}) {
  final engine = AnalysisEngine(BenchmarkData.fromMaps(), _FakeListings(rows));
  return engine.analyze(AnalyzeRequestData(
    mode: 'pc',
    query: query,
    price: price,
    componentType: componentType,
    condition: condition,
  ));
}

void main() {
  group('canonicalCondition', () {
    test('peta UI -> DB dan lolos nilai DB', () {
      expect(canonicalCondition('baru'), 'new');
      expect(canonicalCondition('bekas'), 'second');
      expect(canonicalCondition('new'), 'new');
      expect(canonicalCondition('second'), 'second');
      expect(canonicalCondition('any'), 'any');
    });

    test('kosong/tak dikenal -> any, tak peka huruf', () {
      expect(canonicalCondition(null), 'any');
      expect(canonicalCondition(''), 'any');
      expect(canonicalCondition('rusak'), 'any');
      expect(canonicalCondition('Bekas'), 'second');
      expect(canonicalCondition('BARU'), 'new');
    });
  });

  group('filter kondisi engine (mode pc)', () {
    final mixed3060 = [
      _row('VGA RTX 3060 12GB', 5200000, 'new'),
      _row('MSI RTX 3060 Ventus', 5800000, 'new'),
      _row('VGA RTX 3060', 5000000, 'second'),
      _row('Colorful RTX 3060 12GB', 5500000, 'second'),
    ];

    test("(a) 'bekas' -> hanya baris second, tidak kosong", () async {
      final out = await _analyze(
        mixed3060,
        query: 'RTX 3060',
        price: 5000000,
        componentType: 'gpu',
        condition: 'bekas',
      );
      expect(out.comparisons, isNotEmpty);
      expect(out.comparisons.map((c) => c.condition).toSet(), {'second'});
      expect(out.comparisons.map((c) => c.price).toSet(), {5000000, 5500000});
      expect(out.result.referencePrice, 5250000);
    });

    test("(b) 'baru' -> hanya baris new", () async {
      final out = await _analyze(
        mixed3060,
        query: 'RTX 3060',
        price: 5500000,
        componentType: 'gpu',
        condition: 'baru',
      );
      expect(out.comparisons, isNotEmpty);
      expect(out.comparisons.map((c) => c.condition).toSet(), {'new'});
      expect(out.result.referencePrice, 5500000);
    });

    test("(c) 'bekas' >= 5 baris second -> median, bukan ML", () async {
      final rows = [
        _row('VGA RTX 3060', 5000000, 'second'),
        _row('VGA RTX 3060 12GB', 5200000, 'second'),
        _row('MSI RTX 3060 Ventus', 5500000, 'second'),
        _row('Colorful RTX 3060 12GB', 5800000, 'second'),
        _row('Galax RTX 3060', 6000000, 'second'),
      ];
      final out = await _analyze(
        rows,
        query: 'RTX 3060',
        price: 5500000,
        componentType: 'gpu',
        condition: 'bekas',
      );
      expect(out.comparisons.length, greaterThanOrEqualTo(5));
      expect(out.result.isMlEstimate, isFalse);
      expect(out.result.referencePrice, 5500000);
      expect(out.result.score, 80.0);
    });

    test("(d) kasus 3050: bekas 3,5jt -> median 3,5jt, skor 80, bukan ML",
        () async {
      final rows = [
        _row('VGA RTX 3050', 3300000, 'second'),
        _row('VGA RTX 3050 6GB', 3350000, 'second'),
        _row('MSI RTX 3050 Ventus', 3500000, 'second'),
        _row('Colorful RTX 3050 8GB', 4000000, 'second'),
        _row('Galax RTX 3050 6GB', 4550000, 'second'),
      ];
      final out = await _analyze(
        rows,
        query: 'RTX 3050',
        price: 3500000,
        componentType: 'gpu',
        condition: 'bekas',
      );
      expect(out.comparisons.length, greaterThanOrEqualTo(5));
      expect(out.result.isMlEstimate, isFalse);
      expect(out.result.referencePrice, 3500000);
      expect(out.result.verdict, 'wajar');
      expect(out.result.score, 80.0);
    });

    test("(e) regresi: 'second'=='bekas', 'new'=='baru'", () async {
      final outBekas = await _analyze(
        mixed3060,
        query: 'RTX 3060',
        price: 5000000,
        componentType: 'gpu',
        condition: 'bekas',
      );
      final outSecond = await _analyze(
        mixed3060,
        query: 'RTX 3060',
        price: 5000000,
        componentType: 'gpu',
        condition: 'second',
      );
      expect(
        outBekas.comparisons.map((c) => c.price).toList(),
        outSecond.comparisons.map((c) => c.price).toList(),
      );
      expect(outBekas.result.referencePrice, outSecond.result.referencePrice);
      expect(outBekas.result.score, outSecond.result.score);

      final outBaru = await _analyze(
        mixed3060,
        query: 'RTX 3060',
        price: 5500000,
        componentType: 'gpu',
        condition: 'baru',
      );
      final outNew = await _analyze(
        mixed3060,
        query: 'RTX 3060',
        price: 5500000,
        componentType: 'gpu',
        condition: 'new',
      );
      expect(
        outBaru.comparisons.map((c) => c.price).toList(),
        outNew.comparisons.map((c) => c.price).toList(),
      );
      expect(outBaru.result.referencePrice, outNew.result.referencePrice);
      expect(outBaru.result.score, outNew.result.score);
    });
  });
}
