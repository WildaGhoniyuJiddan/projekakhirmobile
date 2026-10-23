import 'package:flutter_test/flutter_test.dart';
import 'package:worthbang/services/engine/dataset.dart';
import 'package:worthbang/services/engine/suggest.dart';
import 'package:worthbang/services/features/price_check_api.dart';

class _FakeListingsSource implements ListingsSource {
  @override
  Future<List<ListingRow>> pcListings({
    String? modelNum,
    required List<String> categories,
  }) async => [];

  @override
  Future<List<Map<String, Object?>>> laptopUnits({
    required List<String> tokens,
  }) async => [
    {
      'brand': 'Lenovo',
      'model': 'ThinkPad X1 Carbon',
      'cpu': 'i7-1165G7',
      'price': 15000000,
    },
    {
      'brand': 'Lenovo',
      'model': 'IdeaPad Slim 3',
      'cpu': 'Ryzen 5 5500U',
      'price': 7500000,
    },
  ];

  @override
  Future<List<Map<String, Object?>>> pcComponents({
    required List<String> tokens,
  }) async => [
    {
      'component_type': 'gpu',
      'brand': 'Nvidia',
      'model': 'RTX 3060 12GB',
      'sample_count': 10,
      'avg_price': 4200000,
    },
    {
      'component_type': 'cpu',
      'brand': 'AMD',
      'model': 'Ryzen 5 5600',
      'sample_count': 15,
      'avg_price': 1800000,
    },
  ];

  @override
  Future<DateTime?> latestScrapedAt() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SuggestEngine tests', () {
    late SuggestEngine engine;

    setUpAll(() async {
      await BenchmarkData.load();
      engine = SuggestEngine(
        BenchmarkData.instance ?? BenchmarkData.fromMaps(),
        _FakeListingsSource(),
      );
    });

    test('suggestComponents section pc mengenali query gpu dan mengembalikan saran', () async {
      final res = await engine.suggestComponents(
        section: 'pc',
        q: 'rtx 3060',
      );
      expect(res, isNotEmpty);
      final labels = res.map((r) => r['label'] as String).toList();
      expect(labels.any((l) => l.toLowerCase().contains('3060')), isTrue);
    });

    test('suggestComponents section pc mengenali query ram', () async {
      final res = await engine.suggestComponents(
        section: 'pc',
        q: 'ram ddr4',
      );
      expect(res, isNotEmpty);
      final labels = res.map((r) => r['label'] as String).toList();
      expect(labels.any((l) => l.toLowerCase().contains('ddr4')), isTrue);
    });

    test('suggestComponents section laptop mengembalikan saran laptop', () async {
      final res = await engine.suggestComponents(
        section: 'laptop',
        q: 'thinkpad',
      );
      expect(res, isNotEmpty);
      final labels = res.map((r) => r['label'] as String).toList();
      expect(labels.any((l) => l.toLowerCase().contains('thinkpad')), isTrue);
    });
  });

  group('PriceCheckApi.suggest fallback & reliability', () {
    test('suggest mengembalikan daftar string yang bersih', () async {
      final api = PriceCheckApi();
      final pcSuggestions = await api.suggest(section: 'pc', query: 'rtx');
      expect(pcSuggestions, isNotEmpty);
      expect(pcSuggestions.first, isNotEmpty);

      final laptopSuggestions = await api.suggest(section: 'laptop', query: 'thinkpad');
      expect(laptopSuggestions, isNotEmpty);
    });

    test('suggest query kurang dari 2 karakter menghasilkan list kosong', () async {
      final api = PriceCheckApi();
      final res = await api.suggest(section: 'pc', query: 'r');
      expect(res, isEmpty);
    });
  });
}
