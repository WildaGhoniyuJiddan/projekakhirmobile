/// Tes parity ML Fase C — Dart vs Python (`tools/ml/train_price_models.py`).
///
/// Sumber kebenaran: `test/fixtures/ml_parity.json` (fixture final Fase B,
/// byte-identik dengan parity A5) dan `test/fixtures/ml_parity_predictions.json`
/// (prediksi Python dari fitur final fixture + JSON final — digenerasi
/// dengan snippet di bawah; regenerasi bila fixture/JSON berubah):
/// ```
/// python3 -c "
/// import json, math
/// fix = json.load(open('test/fixtures/ml_parity.json'))
/// model = json.load(open('assets/data/price_models.json'))
/// preds = {}
/// for cat in ['gpu','cpu','ram','storage','motherboard','laptop']:
///     cm = model['categories'][cat]; arr = []
///     for c in fix[cat]:
///         f = c['final_features']; mu = cm['intercept']
///         for feat in cm['features']:
///             mu += feat['coef'] * f[feat['name']]
///         s = cm['sigma_log']
///         arr.append({'price': math.exp(mu),
///                     'low': math.exp(mu - 0.67*s),
///                     'high': math.exp(mu + 0.67*s)})
///     preds[cat] = arr
/// json.dump(preds, open('test/fixtures/ml_parity_predictions.json','w'), indent=1)
/// "
/// ```
///
/// Toleransi: ekstraksi ln pakai relatif 1e-9 (fixture menyimpan repr
/// double penuh Python; log Dart vs Python sepakat hingga ~1e-15, jadi
/// 1e-9 longgar tanpa menyembunyikan salah parsing); prediksi pakai
/// relatif 1e-6 sesuai spesifikasi Fase C.
///
/// Catatan fixture: kasus kategori TIDAK menyimpan field kondisi — dummy
/// kondisi di fitur final hanya (1,0) atau (0,1), sehingga kondisi input
/// tes diturunkan dari sana ('new' bila cond_new == 1, 'second' bila
/// cond_second == 1). Yang diuji dari kondisi di sini adalah fungsi
/// pemetaannya, bukan inferensi kondisi listing (inferensi Tokopedia dari
/// judul hanya ada di pipeline latih Python, bukan di app).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:worthbang/services/engine/benchmark.dart';
import 'package:worthbang/services/engine/dataset.dart';
import 'package:worthbang/services/engine/price_model.dart';

Map<String, double> _doubles(Map m) => {
      for (final e in m.entries) e.key as String: (e.value as num).toDouble(),
    };

void _expectClose(
  double got,
  double expected,
  double relTol,
  String label,
) {
  final tol = relTol * (expected.abs() > 1 ? expected.abs() : 1);
  expect(
    (got - expected).abs(),
    lessThanOrEqualTo(tol),
    reason: '$label: got $got, expected $expected (relTol $relTol)',
  );
}

String _sq(String? text) =>
    (text ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

String _short(String s) =>
    s.length > 48 ? '${s.substring(0, 48)}…' : s;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Fixture + JSON model dibaca SINKRON di sini: loop generator test di
  // bawah berjalan saat file di-load, sebelum setUpAll. Hanya katalog
  // benchmark yang butuh load async (rootBundle) dan tetap di setUpAll.
  final models = MlPriceModels.fromJson(
    (jsonDecode(File('assets/data/price_models.json').readAsStringSync())
            as Map)
        .cast<String, dynamic>(),
  );
  final fixture =
      (jsonDecode(File('test/fixtures/ml_parity.json').readAsStringSync())
              as Map)
          .cast<String, dynamic>();
  final expectedPreds = (jsonDecode(
    File('test/fixtures/ml_parity_predictions.json').readAsStringSync(),
  ) as Map)
      .cast<String, dynamic>();

  late Benchmark benchmark;

  setUpAll(() async {
    final data = await BenchmarkData.load();
    benchmark = Benchmark(data);
  });

  group('paritas ekstraksi — 30 kasus kategori', () {
    for (final cat in ['gpu', 'cpu', 'ram', 'storage', 'motherboard', 'laptop']) {
      final cases = fixture[cat] as List;
      for (var i = 0; i < cases.length; i++) {
        final c = cases[i] as Map;
        test('$cat[$i] ${_short(c['raw_title'] as String)}', () {
          final text = '${c['raw_title']} ${c['raw_spec_text']}';
          final finalF = _doubles(c['final_features'] as Map);
          final cond = finalF['cond_new'] == 1.0 ? 'new' : 'second';
          final model = models.category(cat)!;
          final Map<String, double>? got;
          switch (cat) {
            case 'gpu':
              got = mlGpuFeatures(benchmark, text, cond, model);
            case 'cpu':
              got = mlCpuFeatures(benchmark, text, cond, model);
            case 'ram':
              got = mlRamFeatures(text, cond, model);
            case 'storage':
              got = mlStorageFeatures(text, cond, model);
            case 'motherboard':
              got = mlMotherboardFeatures(text, cond, model);
            case 'laptop':
              got = mlLaptopFeatures(
                benchmark,
                cpuText: text,
                gpuText: text,
                ramText: text,
                storageText: text,
                condition: cond,
                model: model,
              );
            default:
              got = null;
          }
          expect(got, isNotNull, reason: 'ekstraksi $cat[$i] null');
          expect(
            Set<String>.from(got!.keys),
            Set<String>.from(finalF.keys),
            reason: 'kunci fitur $cat[$i]',
          );
          for (final k in finalF.keys) {
            _expectClose(got[k]!, finalF[k]!, 1e-9, '$cat[$i] $k');
          }
        });
      }
    }
  });

  group('paritas klasifikasi storage — 3 kasus tipe', () {
    for (final c in (fixture['storage_type_cases'] as List)) {
      final m = c as Map;
      test(m['text'] as String, () {
        final (cap, type) = mlExtractStorageCat(m['text'] as String);
        final expectedType =
            (m['expected'] as String) == 'sata_ssd' ? 'sata_ssd' : null;
        expect(type, expectedType, reason: 'tipe ${m['text']}');
        expect(cap, m['capacity_gb'], reason: 'kapasitas ${m['text']}');
      });
    }
  });

  group('pemetaan kondisi — satu fungsi', () {
    test('baru/new -> (1,0); bekas/second -> (0,1)', () {
      final model = models.category('gpu')!;
      for (final c in ['baru', 'new']) {
        expect(mlConditionDummies(c, model), (1.0, 0.0));
      }
      for (final c in ['bekas', 'second']) {
        expect(mlConditionDummies(c, model), (0.0, 1.0));
      }
    });

    test('any/unknown/kosong/null -> rata-rata defaults JSON', () {
      final model = models.category('gpu')!;
      // Kasus inferensi fixture: condition_input 'any', kategori gpu.
      final infer = (fixture['condition_inference_cases'] as List).last as Map;
      expect(infer['condition_input'], 'any');
      for (final c in ['any', 'unknown', '', null]) {
        final (cn, cs) = mlConditionDummies(c, model);
        _expectClose(cn, (infer['cond_new'] as num).toDouble(), 1e-12, 'any cn');
        _expectClose(cs, (infer['cond_second'] as num).toDouble(), 1e-12, 'any cs');
      }
    });
  });

  group('paritas CPU laptop — 7 kasus resolve', () {
    for (final c in (fixture['laptop_cpu_cases'] as List)) {
      final m = c as Map;
      test(_short(m['text'] as String), () {
        final res = benchmark.resolveCpuLaptopDetailed(m['text'] as String);
        expect(res.tag, m['expected_tag'], reason: 'tag ${m['text']}');
        expect(res.full, m['actual_full'], reason: 'full ${m['text']}');
        if (m['expected_score'] != null) {
          expect(res.entry, isNotNull, reason: 'entry ${m['text']}');
          expect(
            (res.entry!['score'] as num).toDouble(),
            (m['expected_score'] as num).toDouble(),
            reason: 'skor ${m['text']}',
          );
          // Kunci katalog yang dipakai (nama entri) harus squash-sama
          // dengan kunci ekspektasi fixture.
          expect(
            _sq(res.entry!['name'] as String?),
            _sq(m['expected_key'] as String?),
            reason: 'kunci ${m['text']}',
          );
        } else {
          expect(res.entry, isNull, reason: 'entry DROP ${m['text']}');
        }
      });
    }
  });

  group('paritas prediksi — 30 kasus kategori', () {
    for (final cat in ['gpu', 'cpu', 'ram', 'storage', 'motherboard', 'laptop']) {
      final cases = fixture[cat] as List;
      final preds = expectedPreds[cat] as List;
      for (var i = 0; i < cases.length; i++) {
        final c = cases[i] as Map;
        final exp = preds[i] as Map;
        test('$cat[$i] matematika mentah dari fitur final', () {
          final got = models.predict(cat, _doubles(c['final_features'] as Map));
          expect(got, isNotNull, reason: 'predict $cat[$i] null');
          _expectClose(got!.price, (exp['price'] as num).toDouble(), 1e-6,
              '$cat[$i] price');
          _expectClose(got.low, (exp['low'] as num).toDouble(), 1e-6,
              '$cat[$i] low');
          _expectClose(got.high, (exp['high'] as num).toDouble(), 1e-6,
              '$cat[$i] high');
        });
        test('$cat[$i] ujung-ke-ujung (ekstraksi Dart -> prediksi)', () {
          final text = '${c['raw_title']} ${c['raw_spec_text']}';
          final finalF = _doubles(c['final_features'] as Map);
          final cond = finalF['cond_new'] == 1.0 ? 'new' : 'second';
          final got = mlEstimateFor(
            models: models,
            category: cat,
            benchmark: benchmark,
            query: text,
            cpuText: text,
            gpuText: text,
            condition: cond,
          );
          expect(got, isNotNull, reason: 'mlEstimateFor $cat[$i] null');
          _expectClose(got!.price, (exp['price'] as num).toDouble(), 1e-6,
              '$cat[$i] price');
          _expectClose(got.low, (exp['low'] as num).toDouble(), 1e-6,
              '$cat[$i] low');
          _expectClose(got.high, (exp['high'] as num).toDouble(), 1e-6,
              '$cat[$i] high');
        });
      }
    }
  });

  group('gerbang JSON final', () {
    test('Tier 1 nonaktif semua; fallback hanya gpu/cpu/ram/laptop', () {
      for (final cat in ['gpu', 'cpu', 'ram', 'storage', 'motherboard', 'laptop']) {
        expect(models.category(cat)!.enabled, isFalse, reason: '$cat enabled');
      }
      for (final cat in ['gpu', 'cpu', 'ram', 'laptop']) {
        expect(models.isFallbackEnabled(cat), isTrue, reason: '$cat fallback');
      }
      for (final cat in ['storage', 'motherboard']) {
        expect(models.isFallbackEnabled(cat), isFalse, reason: '$cat fallback');
      }
      expect(models.predict('pc', {}), isNull);
    });
  });

  group('kesenjangan terdokumentasi', () {
    test('VRAM tak ter-parse -> median kategori JSON (bukan per model)', () {
      // RTX 4090 ada di katalog tapi tak punya aturan fallback VRAM dan
      // teksnya tak menyebut GB -> Python memakai median per model
      // (tak ada di JSON), Dart memakai median kategori 8.0.
      final feats = mlGpuFeatures(
        benchmark,
        'VGA RTX 4090',
        'second',
        models.category('gpu')!,
      );
      expect(feats, isNotNull);
      expect(feats!['vram_gb'], 8.0);
      expect(feats['ln_passmark']!, greaterThan(0));
    });

    test('storage desimal: 2.0TB -> 2000, 0 -> tak ter-parse', () {
      expect(mlExtractStorageCat('SSD NVMe 2.0TB'), (2000, 'nvme'));
      expect(mlExtractStorageText('SSD 2.0TB'), 2000);
      final (cap, _) = mlExtractStorageCat('SSD NVMe 0GB');
      expect(cap, isNull);
      expect(mlExtractStorageText('SSD 0TB'), isNull);
    });
  });
}
