import 'package:flutter_test/flutter_test.dart';
import 'package:worthbang/models/store_models.dart';
import 'package:worthbang/services/stores_api.dart';

Store _store(int id, String name, Map<String, int> prices, double dist) =>
    Store(
      id: id,
      name: name,
      address: 'Jl. Test',
      lat: -6.2,
      lng: 106.8,
      distanceKm: dist,
      prices: prices,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StoresApi bundled datasets', () {
    test('memuat dan mengurutkan toko Yogyakarta berdasarkan lokasi', () async {
      final stores = await StoresApi().nearby(
        lat: -7.78063,
        lng: 110.37561,
        radiusKm: 10,
      );

      expect(stores, isNotEmpty);
      expect(stores.first.name, 'Computa');
      expect(stores.any((store) => store.name == 'ELS Computer'), isTrue);
      expect(stores.map((store) => store.id).toSet().length, stores.length);
    });

    test('mencari toko berdasarkan nama (query)', () async {
      final stores = await StoresApi().nearby(
        lat: -7.78063,
        lng: 110.37561,
        query: 'ELS',
      );

      expect(stores, isNotEmpty);
      expect(stores.every((s) => s.name.toLowerCase().contains('els')), isTrue);
    });
  });

  group('Store.fromJson (kontrak B4)', () {
    test('parse response lengkap', () {
      final s = Store.fromJson({
        'id': 1,
        'name': 'Toko Komputer ABC',
        'address': 'Jl. Mangga Dua',
        'lat': -6.21,
        'lng': 106.81,
        'distance_km': 1.4,
        'prices': {'RTX 4060': 4550000},
      });
      expect(s.id, 1);
      expect(s.distanceKm, 1.4);
      expect(s.prices['RTX 4060'], 4550000);
    });

    test('toleran field hilang', () {
      final s = Store.fromJson({'name': 'X'});
      expect(s.prices, isEmpty);
      expect(s.distanceKm, 0);
    });
  });

  group('Store.priceFor', () {
    final s = _store(1, 'A', {'RTX 4060 8GB': 4500000}, 1.0);

    test('cocok sebagian case-insensitive', () {
      expect(s.priceFor('rtx 4060'), 4500000);
      expect(s.priceFor('RTX'), 4500000);
    });

    test('tidak cocok → null', () {
      expect(s.priceFor('Ryzen 9'), isNull);
    });
  });

  group('urutan termurah (logika layar)', () {
    test('termurah pertama, tanpa harga di belakang', () {
      final stores = [
        _store(1, 'Mahal', {'RTX 4060': 5000000}, 1.0),
        _store(2, 'TanpaHarga', {}, 0.5),
        _store(3, 'Murah', {'RTX 4060': 4300000}, 5.0),
      ];
      final withPrice = stores
          .map((s) => (store: s, price: s.priceFor('rtx 4060')))
          .toList()
        ..sort((a, b) {
          if (a.price != null && b.price != null) {
            return a.price!.compareTo(b.price!);
          }
          if (a.price != null) return -1;
          if (b.price != null) return 1;
          return a.store.distanceKm.compareTo(b.store.distanceKm);
        });
      expect(withPrice.map((e) => e.store.name),
          ['Murah', 'Mahal', 'TanpaHarga']);
    });
  });
}
