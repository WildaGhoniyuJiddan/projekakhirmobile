/// Alternatif GPU modern didahulukan di atas GTX lawas.
///
/// Kebijakan (Okt 2026): betterAlternatives* mengurutkan kandidat GPU
/// dengan arsitektur modern (RTX / RX 6000+ / Arc) di atas seri GTX,
/// meskipun skor mentah GTX sedikit lebih tinggi. GTX tidak dibuang:
/// ia tetap masuk di urutan setelah modern, dan teks rekomendasi
/// menjelaskan konflik mentah-vs-fitur itu secara eksplisit.
///
/// Seam: Benchmark langsung dengan BenchmarkData.fromMaps() kalengan
/// (tanpa asset) + AnalysisEngine dengan ListingsSource palsu kosong,
/// supaya yang diuji murni logika urutan dan teks advice.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:worthbang/services/engine/analysis_engine.dart';
import 'package:worthbang/services/engine/benchmark.dart';
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

// Katalog PassMark kalengan. Harga USD dipilih supaya estimasi
// (price_usd * 16500 * 1.10) masuk budget Rp3.500.000, kecuali yang
// sengaja dibuat di luar budget (RTX 4060 mahal pada kasus c).
Map<String, dynamic> _gpuBench({int rtx4060Usd = 150}) => {
      'gpu': {
        'geforce rtx 3050': {
          'name': 'GeForce RTX 3050',
          'score': 10000,
          'price_usd': 200,
        },
        'geforce gtx 1080': {
          'name': 'GeForce GTX 1080',
          'score': 14000,
          'price_usd': 180,
        },
        'geforce rtx 4060': {
          'name': 'GeForce RTX 4060',
          'score': 13000,
          'price_usd': rtx4060Usd,
        },
        'geforce gtx 1660 super': {
          'name': 'GeForce GTX 1660 Super',
          'score': 12500,
          'price_usd': 170,
        },
        'geforce gtx 1660': {
          'name': 'GeForce GTX 1660',
          'score': 11000,
          'price_usd': 150,
        },
      },
    };

Map<String, dynamic> _gpuConsensus() => {
      'gpu': {
        'geforce rtx 3050': {
          'name': 'GeForce RTX 3050',
          'consensus_score': 40,
          'price_usd': 200,
          'n_sources': 2,
        },
        'geforce gtx 1080': {
          'name': 'GeForce GTX 1080',
          'consensus_score': 60,
          'price_usd': 180,
          'n_sources': 1,
        },
        'geforce rtx 4060': {
          'name': 'GeForce RTX 4060',
          'consensus_score': 55,
          'price_usd': 150,
          'n_sources': 3,
        },
      },
    };

Future<AnalysisOutcome> _analyzeGpu(
  Map<String, dynamic> bench, {
  required String query,
  required int price,
}) {
  final engine = AnalysisEngine(
    BenchmarkData.fromMaps(bench: bench),
    _EmptyListings(),
  );
  return engine.analyze(AnalyzeRequestData(
    mode: 'pc',
    query: query,
    price: price,
    componentType: 'gpu',
    condition: 'any',
  ));
}

void main() {
  group('deteksi modern vs lawas', () {
    test('RTX / RX 6000+ / Arc = modern; GTX / RX 5000 = lawas', () {
      expect(isModernGpuModel('GeForce RTX 4060'), isTrue);
      expect(isModernGpuModel('GeForce RTX 3050'), isTrue);
      expect(isModernGpuModel('Radeon RX 6600'), isTrue);
      expect(isModernGpuModel('Radeon RX 7900 XTX'), isTrue);
      expect(isModernGpuModel('Intel Arc A770'), isTrue);
      expect(isModernGpuModel('Intel Arc B580'), isTrue);
      expect(isModernGpuModel('GeForce GTX 1080'), isFalse);
      expect(isModernGpuModel('GeForce GTX 1660 Super'), isFalse);
      expect(isModernGpuModel('Radeon RX 580'), isFalse);
      expect(isModernGpuModel('Radeon RX 5700 XT'), isFalse);
      expect(isGtxGpuModel('GeForce GTX 1080'), isTrue);
      expect(isGtxGpuModel('Nvidia GTX 1080-Ti'), isTrue);
      expect(isGtxGpuModel('GeForce RTX 4060'), isFalse);
    });
  });

  group('betterAlternatives (PassMark): RTX didahulukan di atas GTX', () {
    test('RTX 3050 @3,5jt: RTX 4060 di atas GTX 1080 meski skor mentah kalah',
        () {
      final bench = Benchmark(BenchmarkData.fromMaps(bench: _gpuBench()));
      final alts = bench.betterAlternatives('RTX 3050', 'gpu', 3500000, 16500);
      expect(alts, hasLength(2));
      expect(alts[0]['name'], 'GeForce RTX 4060');
      expect(alts[0]['gain_percent'], 30);
      expect(alts[1]['name'], 'GeForce GTX 1080');
      expect(alts[1]['gain_percent'], 40);
    });

    test('CPU tidak berubah: tetap urut skor desc', () {
      final bench = Benchmark(BenchmarkData.fromMaps(bench: {
        'cpu': {
          'amd ryzen 5 5600': {
            'name': 'AMD Ryzen 5 5600',
            'score': 20000,
            'price_usd': 150,
          },
          'amd ryzen 9 3900x': {
            'name': 'AMD Ryzen 9 3900X',
            'score': 30000,
            'price_usd': 140,
          },
          'intel core i5-12600': {
            'name': 'Intel Core i5-12600',
            'score': 28000,
            'price_usd': 140,
          },
        },
      }));
      final alts =
          bench.betterAlternatives('Ryzen 5 5600', 'cpu', 2600000, 16500);
      expect(alts, hasLength(2));
      expect(alts[0]['name'], 'AMD Ryzen 9 3900X');
      expect(alts[1]['name'], 'Intel Core i5-12600');
    });
  });

  group('betterAlternativesConsensus: seleksi PassMark + RTX didahulukan',
      () {
    test('RTX 3050 @3,5jt: RTX 4060 (13000) di atas GTX 1080 (14000)', () {
      // ALASAN PERUBAHAN (Okt 2026, perintah Dan): seleksi kini memakai
      // PassMark, bukan skor konsensus. Data kalengan lama hanya berisi
      // peta konsensus (RTX 4060: 55, GTX 1080: 60) sehingga di bawah
      // aturan baru fungsi mengembalikan kosong; tes ini kini memakai
      // peta PassMark yang sama dengan grup PassMark di atas (input 3050
      // = 10000, ambang 10% = 11000, keduanya lolos) dan menegaskan
      // RTX tetap didahulukan meski skor PassMark mentahnya kalah, dengan
      // gain dari rasio PassMark (4060: +30%, 1080: +40%).
      final bench = Benchmark(BenchmarkData.fromMaps(bench: _gpuBench()));
      final alts = bench.betterAlternativesConsensus(
          'RTX 3050', 'gpu', 3500000, 16500);
      expect(alts, hasLength(2));
      expect(alts[0]['name'], 'GeForce RTX 4060');
      expect(alts[0]['score'], 13000);
      expect(alts[0]['gain_percent'], 30);
      expect(alts[1]['name'], 'GeForce GTX 1080');
      expect(alts[1]['score'], 14000);
      expect(alts[1]['gain_percent'], 40);
    });

    test('input tanpa PassMark → kosong (tanpa fallback konsensus)', () {
      // Di bawah aturan baru, model yang hanya ada di peta konsensus
      // (tanpa skor PassMark) tidak menghasilkan alternatif.
      final bench =
          Benchmark(BenchmarkData.fromMaps(consensus: _gpuConsensus()));
      final alts = bench.betterAlternativesConsensus(
          'RTX 3050', 'gpu', 3500000, 16500);
      expect(alts, isEmpty);
    });
  });

  group('teks recommendation: catatan RTX vs raw GTX', () {
    test('input GTX 1660: sarankan RTX 4060, sebut GTX 1080 +27% raw', () async {
      final outcome = await _analyzeGpu(_gpuBench(),
          query: 'GTX 1660', price: 3500000);
      expect(outcome.alternatives, hasLength(2));
      expect(outcome.alternatives[0].name, 'GeForce RTX 4060');
      final rec = outcome.result.recommendation;
      expect(rec, contains('RTX 4060'));
      expect(rec, contains('GTX 1080'));
      expect(rec, contains('+27%'));
      expect(rec, contains('raw performance'));
      expect(rec, contains('DLSS'));
    });

    test('input RTX 3050 dengan RTX 4060 di budget: RTX didahulukan + catatan',
        () async {
      final outcome = await _analyzeGpu(_gpuBench(),
          query: 'RTX 3050', price: 3500000);
      expect(outcome.alternatives, hasLength(2));
      expect(outcome.alternatives[0].name, 'GeForce RTX 4060');
      expect(outcome.alternatives[1].name, 'GeForce GTX 1080');
      final rec = outcome.result.recommendation;
      expect(rec, contains('utamakan seri RTX'));
      expect(rec, contains('RTX 4060'));
      expect(rec, contains('GTX 1080'));
      expect(rec, contains('+40%'));
      expect(rec, contains('raw performance'));
    });

    test('input RTX 3050 tanpa RTX lain di budget: jangan suruh pindah ke GTX',
        () async {
      // RTX 4060 dibuat di luar budget (USD 250 -> estimasi Rp4.537.500),
      // sehingga satu-satunya alternatif di atas input hanyalah GTX.
      final outcome = await _analyzeGpu(_gpuBench(rtx4060Usd: 250),
          query: 'RTX 3050', price: 3500000);
      expect(outcome.alternatives[0].name, 'GeForce GTX 1080');
      final rec = outcome.result.recommendation;
      expect(rec, contains('sudah unggul'));
      expect(rec, contains('DLSS'));
      expect(rec, contains('GTX 1080'));
      expect(rec, contains('+40%'));
      expect(rec, contains('murni mengejar raw performance'));
      expect(rec, isNot(contains('utamakan seri')));
    });
  });
}
