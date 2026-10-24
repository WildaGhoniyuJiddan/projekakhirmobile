/// Pesan eksplisit P5 saat advice benchmark kosong (jalur PC, non-ML).
///
/// (Okt 2026, perintah Dan): bila advice kosong, rekomendasi mendapat
/// suffix eksplisit, dibedakan dari data yang ada di situs tempel:
/// model dikenali (PassMark/konsensus ada) tapi tidak ada alternatif
/// yang muat budget vs model tidak dikenali sama sekali. Jalur laptop
/// tidak diubah; jalur ML tidak ditempeli pesan ini (diuji di
/// ml_verdict_range_test.dart).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:worthbang/services/engine/analysis_engine.dart';
import 'package:worthbang/services/engine/dataset.dart';

class _EmptyListings implements ListingsSource {
  @override
  Future<List<ListingRow>> pcListings({
    String? modelNum,
    required List<String> categories,
  }) async =>
      [];

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BenchmarkData data;
  setUpAll(() async {
    data = await BenchmarkData.load();
  });

  Future<AnalysisOutcome> analyzePc(String query, int price) async {
    final engine = AnalysisEngine(data, _EmptyListings());
    return engine.analyze(AnalyzeRequestData(
      mode: 'pc',
      query: query,
      price: price,
      componentType: 'gpu',
      condition: 'any',
    ));
  }

  group('pesan eksplisit P5 saat advice kosong', () {
    test('model dikenali, tak ada alternatif muat budget -> pesan budget',
        () async {
      // Bentuk pendek 'GTX 1050 TI' me-resolve ke PassMark 6366, tapi
      // tidak ada kandidat >= 10% yang muat budget estimasi @950rb.
      // (Query lengkap hasil P1 TIDAK me-resolve di lookup benchmark —
      // lihat komentar di tes P4; cabang dikenali diuji di sini dengan
      // bentuk pendek, cabang tak-dikenali diuji oleh tes berikutnya.)
      final out = await analyzePc('GTX 1050 TI', 950000);
      expect(out.alternatives, isEmpty);
      expect(out.result.recommendation, contains(
          'Tidak ada alternatif benchmark yang lebih baik dalam budget ini.'));
    });

    test('model tidak dikenali -> pesan tidak dikenali', () async {
      final out = await analyzePc('Komponen Ngawur', 5000000);
      expect(out.alternatives, isEmpty);
      expect(out.result.recommendation, contains(
          'Model ini tidak dikenali di data benchmark, jadi tidak ada alternatif yang bisa disarankan.'));
    });
  });
}
