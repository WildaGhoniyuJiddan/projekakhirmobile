/// Seam fungsi top-level benchmark (per docs/CONTRACTS.md): padanan
/// modul benchmark.py Python yang dataset-nya global. Dataset dimuat
/// sekali via BenchmarkData.load() (mengisi BenchmarkData.instance);
/// fungsi di sini membungkus kelas Benchmark dengan view bertipe.
library;

import 'benchmark.dart';
import 'dataset.dart';

Benchmark get _bench {
  final data = BenchmarkData.instance;
  if (data == null) {
    throw StateError(
      'BenchmarkData.load() harus dipanggil sebelum memakai benchmark_api.',
    );
  }
  return Benchmark(data);
}

num? _num(Map<String, dynamic> m, String key) => (m[key] as num?);

/// View bertipe atas entri katalog benchmark/konsensus (map mentah).
class BenchEntryView {
  const BenchEntryView(this.raw);

  final Map<String, dynamic> raw;

  String get name => raw['name'] as String? ?? '';
  num? get score => _num(raw, 'score');
  double? get priceUsd => _num(raw, 'price_usd')?.toDouble();

  // Field khusus entri konsensus.
  double? get consensusScore => _num(raw, 'consensus_score')?.toDouble();
  String? get tier => raw['tier'] as String?;
  int? get nSources => _num(raw, 'n_sources')?.toInt();
  double? get agreement => _num(raw, 'agreement')?.toDouble();
}

/// View bertipe atas alternatif (map hasil betterAlternatives*).
class AlternativeView {
  const AlternativeView(this.raw);

  final Map<String, Object?> raw;

  String get name => raw['name'] as String? ?? '';
  int get score => (raw['score'] as num? ?? 0).toInt();
  int get estPriceIdr => (raw['est_price_idr'] as num? ?? 0).toInt();
  int get gainPercent => (raw['gain_percent'] as num? ?? 0).toInt();
  int? get vramGb => (raw['vram_gb'] as num?)?.toInt();
  String? get tierLabel => raw['tier_label'] as String?;
  int? get nSources => (raw['n_sources'] as num?)?.toInt();
  String? get scoreSource => raw['score_source'] as String?;
}

/// View bertipe atas hasil laptopComboScore.
class LaptopComboView {
  const LaptopComboView(this.raw);

  final Map<String, Object?> raw;

  num? get score => raw['score'] as num?;
  bool get isIgpu => raw['is_igpu'] as bool? ?? false;
  String? get tierLabel => raw['tier_label'] as String?;

  BenchEntryView? get gpu {
    final g = raw['gpu'];
    return g is Map<String, dynamic> ? BenchEntryView(g) : null;
  }

  BenchEntryView? get cpu {
    final c = raw['cpu'];
    return c is Map<String, dynamic> ? BenchEntryView(c) : null;
  }
}

BenchEntryView? passmarkScore(String query, String? componentType) {
  final e = _bench.passmarkScore(query, componentType);
  return e == null ? null : BenchEntryView(e);
}

BenchEntryView? consensusLookup(String query, String? componentType) {
  final e = _bench.consensusLookup(query, componentType);
  return e == null ? null : BenchEntryView(e);
}

String getTierLabel(num? score, String? componentType) =>
    _bench.getTierLabel(score, componentType);

String consensusTierLabel(num? score) => _bench.consensusTierLabel(score);

int? extractVramGb(String? text) => _bench.extractVramGb(text);

List<AlternativeView> betterAlternatives(
  String query,
  String? componentType,
  int priceIdr,
  double usdToIdr, {
  int maxResults = 2,
}) =>
    _bench
        .betterAlternatives(
          query,
          componentType,
          priceIdr,
          usdToIdr,
          maxResults: maxResults,
        )
        .map(AlternativeView.new)
        .toList();

List<AlternativeView> betterAlternativesConsensus(
  String query,
  String? componentType,
  int priceIdr,
  double usdToIdr, {
  int maxResults = 2,
}) =>
    _bench
        .betterAlternativesConsensus(
          query,
          componentType,
          priceIdr,
          usdToIdr,
          maxResults: maxResults,
        )
        .map(AlternativeView.new)
        .toList();

LaptopComboView? laptopComboScore(String? cpuText, String? gpuText) {
  final c = _bench.laptopComboScore(cpuText, gpuText);
  return c == null ? null : LaptopComboView(c);
}
