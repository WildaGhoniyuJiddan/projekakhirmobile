import 'package:flutter_test/flutter_test.dart';
import 'package:worthbang/widgets/verdict_badge.dart';
import 'package:worthbang/models/price_check_models.dart';

void main() {
  group('AnalysisResult.fromJson (kontrak /analyze)', () {
    test('parse response lengkap', () {
      final r = AnalysisResult.fromJson({
        'mode': 'pc',
        'query': 'RTX 4060',
        'input_price': 4500000,
        'score': 82.5,
        'verdict': 'wajar',
        'recommendation': 'Ok.',
        'reference_price': 4600000,
        'price_delta_percent': -2.2,
        'fair_price_low': 4200000,
        'fair_price_high': 4900000,
        'comparisons': [
          {
            'title': 'RTX 4060 8GB',
            'price': 4550000,
            'source': 'tokopedia',
            'listing_url': 'https://x',
            'similarity': 0.92,
            'condition': 'baru',
          },
        ],
        'alternatives': [
          {
            'name': 'RTX 4060 Ti',
            'score': 12345,
            'est_price_idr': 6800000,
            'gain_percent': 18.0,
          },
        ],
        'freshness': {'label': '1 jam lalu', 'is_stale': false},
      });
      expect(r.query, 'RTX 4060');
      expect(r.inputPrice, 4500000);
      expect(r.score, 82.5);
      expect(r.listingCount, 1);
      expect(r.comparisons.first.condition, 'baru');
      expect(r.alternatives.first.gainPercent, 18.0);
      expect(r.freshnessLabel, '1 jam lalu');
      expect(r.isStale, isFalse);
    });

    test('toleran field hilang', () {
      final r = AnalysisResult.fromJson({'query': 'X'});
      expect(r.inputPrice, 0);
      expect(r.comparisons, isEmpty);
      expect(r.freshnessLabel, isNull);
    });
  });

  group('verdictFromString', () {
    test('mapping verdict kontrak', () {
      expect(verdictFromString('worth it'), Verdict.good);
      expect(verdictFromString('Worth It'), Verdict.good);
      expect(verdictFromString('wajar'), Verdict.fair);
      expect(verdictFromString('ada opsi lebih baik'), Verdict.fair);
      expect(verdictFromString('data terbatas'), Verdict.fair);
      expect(verdictFromString('kemahalan'), Verdict.bad);
    });
  });
}
