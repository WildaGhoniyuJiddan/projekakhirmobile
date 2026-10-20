import 'package:flutter_test/flutter_test.dart';
import 'package:worthbang/models/price_check_models.dart';
import 'package:worthbang/models/search_filter.dart';

List<PriceComparison> _sample() => const [
      PriceComparison(
          title: 'A', price: 5000000, source: 'tokopedia', condition: 'baru', similarity: 0.9),
      PriceComparison(
          title: 'B', price: 3000000, source: 'shopee', condition: 'bekas', similarity: 0.95),
      PriceComparison(
          title: 'C', price: 4500000, source: 'tokopedia', condition: 'bekas', similarity: 0.8),
    ];

void main() {
  group('SearchFilter', () {
    test('default: semua, urut harga termurah', () {
      final out = const SearchFilter().apply(_sample());
      expect(out.map((e) => e.title), ['B', 'C', 'A']);
    });

    test('filter kondisi', () {
      final out = const SearchFilter(conditions: {'baru'}).apply(_sample());
      expect(out.map((e) => e.title), ['A']);
    });

    test('filter sumber', () {
      final out =
          const SearchFilter(sources: {'shopee'}).apply(_sample());
      expect(out.map((e) => e.title), ['B']);
    });

    test('filter harga maks', () {
      final out = const SearchFilter(maxPrice: 4000000).apply(_sample());
      expect(out.map((e) => e.title), ['B']);
    });

    test('sort harga tertinggi & kemiripan', () {
      expect(
        const SearchFilter(sort: SortOption.priceDesc)
            .apply(_sample())
            .map((e) => e.title),
        ['A', 'C', 'B'],
      );
      expect(
        const SearchFilter(sort: SortOption.similarity)
            .apply(_sample())
            .map((e) => e.title),
        ['B', 'A', 'C'],
      );
    });

    test('kombinasi filter', () {
      final out = const SearchFilter(
        conditions: {'bekas'},
        sources: {'tokopedia'},
      ).apply(_sample());
      expect(out.map((e) => e.title), ['C']);
    });

    test('copyWith', () {
      const f = SearchFilter();
      final f2 = f.copyWith(sort: SortOption.priceDesc);
      expect(f2.sort, SortOption.priceDesc);
      expect(f2.conditions, isEmpty);
      final f3 = f2.copyWith(maxPrice: () => null);
      expect(f3.maxPrice, isNull);
    });
  });
}
