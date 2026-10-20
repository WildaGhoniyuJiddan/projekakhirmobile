/// Model POST /api/v1/analyze-bundle — mengikuti API_CONTRACT.md.
class BundleInputItem {
  const BundleInputItem({
    required this.query,
    required this.price,
    this.componentType,
  });

  final String query;
  final int price;
  final String? componentType;

  Map<String, dynamic> toJson() => {
        'query': query,
        'price': price,
        if (componentType != null) 'component_type': componentType,
      };
}

class BundleResultItem {
  const BundleResultItem({
    required this.query,
    required this.price,
    this.referencePrice,
    this.score,
    this.verdict,
  });

  final String query;
  final int price;
  final int? referencePrice;
  final double? score;
  final String? verdict;

  factory BundleResultItem.fromJson(Map<String, dynamic> json) =>
      BundleResultItem(
        query: json['query'] as String? ?? '',
        price: (json['price'] as num? ?? 0).toInt(),
        referencePrice: (json['reference_price'] as num?)?.toInt(),
        score: (json['score'] as num?)?.toDouble(),
        verdict: json['verdict'] as String?,
      );
}

class BundleResult {
  const BundleResult({
    required this.bundlePrice,
    this.referenceTotal,
    required this.score,
    required this.verdict,
    this.recommendation,
    this.savingsPercent,
    this.items = const [],
  });

  final int bundlePrice;
  final int? referenceTotal;
  final double score;
  final String verdict;
  final String? recommendation;
  final double? savingsPercent;
  final List<BundleResultItem> items;

  factory BundleResult.fromJson(Map<String, dynamic> json) =>
      BundleResult(
        bundlePrice: (json['bundle_price'] as num? ?? 0).toInt(),
        referenceTotal: (json['reference_total'] as num?)?.toInt(),
        score: (json['score'] as num? ?? 0).toDouble(),
        verdict: json['verdict'] as String? ?? 'data terbatas',
        recommendation: json['recommendation'] as String?,
        savingsPercent: (json['savings_percent'] as num?)?.toDouble(),
        items: (json['items'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(BundleResultItem.fromJson)
            .toList(),
      );
}
