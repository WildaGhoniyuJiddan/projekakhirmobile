import 'package:flutter_test/flutter_test.dart';
import 'package:worthbang/models/bundle_models.dart';

void main() {
  group('BundleResult.fromJson (kontrak /analyze-bundle)', () {
    test('parse response lengkap', () {
      final r = BundleResult.fromJson({
        'bundle_price': 8500000,
        'reference_total': 9000000,
        'score': 78.0,
        'verdict': 'wajar',
        'recommendation': 'Ok.',
        'savings_percent': 5.5,
        'items': [
          {
            'query': 'Ryzen 5 5600',
            'price': 1800000,
            'reference_price': 1850000,
            'score': 80.0,
            'verdict': 'wajar',
          },
        ],
      });
      expect(r.bundlePrice, 8500000);
      expect(r.referenceTotal, 9000000);
      expect(r.savingsPercent, 5.5);
      expect(r.items.length, 1);
      expect(r.items.first.verdict, 'wajar');
    });

    test('toleran field hilang', () {
      final r = BundleResult.fromJson({'bundle_price': 1000});
      expect(r.score, 0);
      expect(r.items, isEmpty);
      expect(r.verdict, 'data terbatas');
    });

    test('BundleInputItem.toJson sesuai kontrak request', () {
      final json = const BundleInputItem(
        query: 'Ryzen 5 5600',
        price: 1800000,
        componentType: 'cpu',
      ).toJson();
      expect(json['query'], 'Ryzen 5 5600');
      expect(json['price'], 1800000);
      expect(json['component_type'], 'cpu');
    });
  });
}
