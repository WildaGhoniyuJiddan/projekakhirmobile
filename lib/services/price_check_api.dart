import 'package:worthbang/models/bundle_models.dart';
import 'package:worthbang/models/price_check_models.dart';
import 'package:worthbang/services/api_exception.dart';
import 'package:worthbang/services/engine/analysis_engine.dart';
import 'package:worthbang/services/engine/dataset.dart';
import 'package:worthbang/services/engine/suggest.dart';
import 'package:worthbang/services/supabase_listings_source.dart';

/// Akses analisis harga — sekarang dihitung LOKAL oleh engine Dart
/// (port analysis.py/suggest.py) dengan listing dari Supabase.
///
/// Interface publik dipertahankan dari era backend Python agar
/// screens/providers tidak berubah. Engine dibuat malas (lazy) dari
/// dataset asset + SupabaseListingsSource; bisa diinjeksikan untuk test.
class PriceCheckApi {
  PriceCheckApi({this._engine, SuggestEngine? suggestEngine})
      : _suggestEngine = suggestEngine;

  AnalysisEngine? _engine;
  SuggestEngine? _suggestEngine;

  Future<AnalysisEngine> _ensureEngine() async {
    final existing = _engine;
    if (existing != null) return existing;
    final data = BenchmarkData.instance ?? await BenchmarkData.load();
    return _engine = AnalysisEngine(data, SupabaseListingsSource());
  }

  Future<SuggestEngine> _ensureSuggest() async {
    final existing = _suggestEngine;
    if (existing != null) return existing;
    final data = BenchmarkData.instance ?? await BenchmarkData.load();
    return _suggestEngine = SuggestEngine(data, SupabaseListingsSource());
  }

  /// Analisis kelayakan satu harga (dulu POST /api/v1/analyze).
  Future<AnalysisResult> analyze({
    required String mode, // 'pc' | 'laptop'
    required String query,
    required int price,
    String? componentType,
    String condition = 'any', // 'any' | 'baru' | 'bekas'
  }) async {
    final engine = await _ensureEngine();
    final outcome = await engine.analyze(
      AnalyzeRequestData(
        mode: mode,
        query: query,
        price: price,
        componentType: componentType,
        condition: condition,
      ),
    );
    final r = outcome.result;
    return AnalysisResult(
      mode: mode,
      query: query,
      inputPrice: price,
      score: r.score,
      verdict: r.verdict,
      recommendation: r.recommendation,
      referencePrice: r.referencePrice,
      priceDeltaPercent: r.deltaPercent,
      fairPriceLow: r.fairPriceLow,
      fairPriceHigh: r.fairPriceHigh,
      comparisons: outcome.comparisons.map(_mapComparison).toList(),
      alternatives: outcome.alternatives
          .map(
            (a) => Alternative(
              name: a.name,
              score: a.score,
              estPriceIdr: a.estPriceIdr,
              gainPercent: a.gainPercent.toDouble(),
            ),
          )
          .toList(),
      freshnessLabel: outcome.freshness.label,
      isStale: outcome.freshness.isStale,
    );
  }

  /// Pencarian listing tanpa analisis benchmark (dulu POST /api/v1/search).
  Future<List<PriceComparison>> search({
    required String mode,
    required String query,
    String? componentType,
    String condition = 'any',
  }) async {
    final engine = await _ensureEngine();
    final rows = await engine.search(
      AnalyzeRequestData(
        mode: mode,
        query: query,
        componentType: componentType,
        condition: condition,
      ),
    );
    return rows.map(_mapComparison).toList();
  }

  /// Analisis paket 1–6 komponen (dulu POST /api/v1/analyze-bundle).
  Future<BundleResult> analyzeBundle({
    required List<BundleInputItem> items,
    required int bundlePrice,
    String condition = 'any',
  }) async {
    final engine = await _ensureEngine();
    try {
      final outcome = await engine.analyzeBundle(
        items: items,
        bundlePrice: bundlePrice,
        condition: condition,
      );
      return BundleResult(
        bundlePrice: outcome.bundlePrice,
        referenceTotal: outcome.referenceTotal,
        score: outcome.score,
        verdict: outcome.verdict,
        recommendation: outcome.recommendation,
        savingsPercent: outcome.savingsPercent,
        items: outcome.items
            .map(
              (d) => BundleResultItem(
                query: d.query,
                price: d.priceInput ?? 0,
                referencePrice: d.referencePrice,
              ),
            )
            .toList(),
      );
    } on BundleReferenceException catch (e) {
      // Padanan HTTP 422 backend lama.
      throw ApiException(e.detail, 422);
    }
  }

  /// Autocomplete komponen/laptop (dulu GET /api/v1/suggest/{section}).
  Future<List<String>> suggest({
    required String section, // 'pc' | 'laptop'
    required String query,
    int limit = 8,
  }) async {
    if (query.trim().length < 2) return const [];
    final engine = await _ensureSuggest();
    final rows = await engine.suggestComponents(
      section: section,
      q: query,
      limit: limit,
    );
    return rows
        .map((r) => (r['label'] as String? ?? '').trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  PriceComparison _mapComparison(ComparisonData c) => PriceComparison(
    title: c.title,
    price: c.price,
    source: c.source,
    listingUrl: c.listingUrl,
    similarity: c.similarity,
    condition: c.condition,
  );
}
