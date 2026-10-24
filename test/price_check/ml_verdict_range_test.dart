/// Verdict + skor jalur ML mengikuti rentang perkiraan [low, high].
///
/// (Okt 2026, perintah Dan): harga <= low = worth it (90 + min(10, ...)),
/// low < harga <= high = wajar (linear 84 -> 55), harga > high =
/// kemahalan (50 - min(50, ...)), skor dibulatkan ke bilangan bulat.
/// Rekomendasi jalur ML menyebut perkiraan dan TIDAK mengandung
/// "opsi lebih baik" — baik sebagai teks maupun daftar alternatif
/// (keduanya ditekan di jalur ML; lihat mlFired di analysis_engine).
///
/// Seam: BenchmarkData + price_models.json ASLI (bukan kalengan),
/// ListingsSource kosong (0 pembanding -> jalur ML menyala untuk
/// kondisi 'second'), sehingga estimasi/range yang dipakai tes adalah
/// parameter model GPU sebenarnya — bukan tautologi.
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthbang/services/engine/analysis_engine.dart';
import 'package:worthbang/services/engine/dataset.dart';
import 'package:worthbang/services/engine/price_model.dart';

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
  late MlPriceModels models;

  setUpAll(() async {
    data = await BenchmarkData.load();
    final text = await rootBundle.loadString('assets/data/price_models.json');
    models = MlPriceModels.fromJson(
        (jsonDecode(text) as Map).cast<String, dynamic>());
  });

  Future<AnalysisOutcome> analyzeGpu(int price) async {
    final engine = AnalysisEngine(data, _EmptyListings(), priceModels: models);
    return engine.analyze(AnalyzeRequestData(
      mode: 'pc',
      query: 'RTX 4060',
      price: price,
      componentType: 'gpu',
      condition: 'second',
    ));
  }

  /// Probe: ambil estimasi + rentang model GPU dari engine nyata.
  Future<({int estimate, int low, int high})> probe() async {
    final out = await analyzeGpu(5000000);
    expect(out.result.isMlEstimate, isTrue,
        reason: 'listings kosong + kondisi second -> jalur ML harus menyala');
    return (
      estimate: out.result.referencePrice,
      low: out.result.fairPriceLow,
      high: out.result.fairPriceHigh,
    );
  }

  group('verdict jalur ML mengikuti rentang perkiraan', () {
    test('harga 1,30x estimasi GPU bukan kemahalan', () async {
      // 1,30x < faktor high GPU (exp(0,67 * sigma 0,4641) = 1,3647),
      // jadi harga ini masih di dalam rentang -> wajar, bukan kemahalan.
      final p = await probe();
      final out = await analyzeGpu((p.estimate * 1.30).round());
      expect(out.result.verdict, 'wajar');
      expect(out.result.score, inInclusiveRange(55, 84));
      expect(out.result.score, out.result.score.truncateToDouble(),
          reason: 'skor jalur ML dibulatkan ke bilangan bulat');
      expect(out.result.recommendation, contains('perkiraan'));
      expect(out.result.recommendation, isNot(contains('opsi lebih baik')));
      expect(out.alternatives, isEmpty,
          reason: 'jalur ML tidak menampilkan daftar opsi lebih baik');
    });

    test('di atas high = kemahalan; di bawah low = worth it', () async {
      final p = await probe();
      final over = await analyzeGpu(p.high + 100000);
      expect(over.result.verdict, 'kemahalan');
      expect(over.result.score, inInclusiveRange(0, 50));
      expect(over.result.score, over.result.score.truncateToDouble(),
          reason: 'skor jalur ML dibulatkan ke bilangan bulat');
      expect(over.result.recommendation, contains('perkiraan'));
      expect(over.result.recommendation, isNot(contains('opsi lebih baik')));
      expect(over.alternatives, isEmpty);

      final under = await analyzeGpu(p.low ~/ 2);
      expect(under.result.verdict, 'worth it');
      expect(under.result.score, inInclusiveRange(90, 100));
      expect(under.result.recommendation, contains('perkiraan'));
      expect(under.result.recommendation, isNot(contains('opsi lebih baik')));
      expect(under.alternatives, isEmpty);
    });

    test('jalur ML tidak ditempeli pesan P5 (advice kosong)', () async {
      // P5 hanya untuk jalur PC non-ML: rekomendasi ML berdiri sendiri
      // sebagai perkiraan, tanpa suffix "tidak ada alternatif...".
      final out = await analyzeGpu(5000000);
      expect(out.result.isMlEstimate, isTrue);
      expect(out.result.recommendation,
          isNot(contains('Tidak ada alternatif benchmark')));
      expect(out.result.recommendation, isNot(contains('tidak dikenali')));
    });
  });
}
