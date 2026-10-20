import 'package:worthbang/widgets/verdict_badge.dart';

/// Model hasil POST /api/v1/analyze — bentuk mengikuti API_CONTRACT.md.
///
/// Parser toleran: field opsional boleh absen (mis. dari FakeApiClient lama).
class PriceComparison {
  const PriceComparison({
    required this.title,
    required this.price,
    required this.source,
    this.listingUrl,
    this.similarity,
    this.condition,
  });

  final String title;
  final int price;
  final String source;
  final String? listingUrl;
  final double? similarity;
  final String? condition;

  factory PriceComparison.fromJson(Map<String, dynamic> json) =>
      PriceComparison(
        title: json['title'] as String? ?? '-',
        price: (json['price'] as num? ?? 0).toInt(),
        source: json['source'] as String? ?? '-',
        listingUrl: json['listing_url'] as String?,
        similarity: (json['similarity'] as num?)?.toDouble(),
        condition: json['condition'] as String?,
      );
}

class Alternative {
  const Alternative({
    required this.name,
    required this.score,
    required this.estPriceIdr,
    this.gainPercent,
  });

  final String name;
  final int score;
  final int estPriceIdr;
  final double? gainPercent;

  factory Alternative.fromJson(Map<String, dynamic> json) => Alternative(
        name: json['name'] as String? ?? '-',
        score: (json['score'] as num? ?? 0).toInt(),
        estPriceIdr: (json['est_price_idr'] as num? ?? 0).toInt(),
        gainPercent: (json['gain_percent'] as num?)?.toDouble(),
      );
}

class AnalysisResult {
  const AnalysisResult({
    required this.mode,
    required this.query,
    required this.inputPrice,
    required this.score,
    required this.verdict,
    this.recommendation,
    this.referencePrice,
    this.priceDeltaPercent,
    this.fairPriceLow,
    this.fairPriceHigh,
    this.comparisons = const [],
    this.alternatives = const [],
    this.freshnessLabel,
    this.isStale = false,
  });

  final String mode;
  final String query;
  final int inputPrice;
  final double score;
  final String verdict;
  final String? recommendation;
  final int? referencePrice;
  final double? priceDeltaPercent;
  final int? fairPriceLow;
  final int? fairPriceHigh;
  final List<PriceComparison> comparisons;
  final List<Alternative> alternatives;
  final String? freshnessLabel;
  final bool isStale;

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    final freshness = json['freshness'] as Map<String, dynamic>?;
    return AnalysisResult(
      mode: json['mode'] as String? ?? 'pc',
      query: json['query'] as String? ?? '',
      inputPrice: (json['input_price'] as num? ?? 0).toInt(),
      score: (json['score'] as num? ?? 0).toDouble(),
      verdict: json['verdict'] as String? ?? 'data terbatas',
      recommendation: json['recommendation'] as String?,
      referencePrice: (json['reference_price'] as num?)?.toInt(),
      priceDeltaPercent: (json['price_delta_percent'] as num?)?.toDouble(),
      fairPriceLow: (json['fair_price_low'] as num?)?.toInt(),
      fairPriceHigh: (json['fair_price_high'] as num?)?.toInt(),
      comparisons: (json['comparisons'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PriceComparison.fromJson)
          .toList(),
      alternatives: (json['alternatives'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Alternative.fromJson)
          .toList(),
      freshnessLabel: freshness?['label'] as String?,
      isStale: freshness?['is_stale'] as bool? ?? false,
    );
  }

  /// Jumlah listing pembanding (untuk klaim "N listing" di UI).
  int get listingCount => comparisons.length;
}

/// Petakan string verdict backend ke [Verdict] UI.
///
/// Kontrak: "worth it" | "wajar" | "ada opsi lebih baik" | "kemahalan" |
/// "data terbatas".
Verdict verdictFromString(String verdict) {
  final v = verdict.toLowerCase();
  if (v.contains('worth it') || v.contains('murah')) return Verdict.good;
  if (v.contains('mahal')) return Verdict.bad;
  return Verdict.fair;
}
