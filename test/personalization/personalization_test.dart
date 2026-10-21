import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worthbang/services/data/local_catalog.dart';
import 'package:worthbang/services/features/personalization/personalization_engine.dart';

final t0 = DateTime(2026, 1, 1, 12);

const catalog = [
  CatalogItem(model: 'AMD Radeon RX 7800 XT 16GB', price: 8500000),
  CatalogItem(model: 'NVIDIA GeForce RTX 4070 12GB', price: 9500000),
  CatalogItem(model: 'AMD Ryzen 7 7800X3D', price: 6800000),
  CatalogItem(model: 'Intel Core i5-12400F', price: 2100000),
  CatalogItem(model: 'Intel Core i3-12100F', price: 1500000),
  CatalogItem(model: 'Motherboard ASUS ROG B650E', price: 4200000),
  CatalogItem(model: 'RAM Kingston Fury DDR5 32GB', price: 1600000),
  CatalogItem(model: 'SSD Samsung 990 Pro NVMe 1TB', price: 1900000),
];

Future<PersonalizationEngine> freshEngine({
  Map<String, double>? worth,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return PersonalizationEngine(prefs, worthByNameKey: worth);
}

Future<PersonalizationEngine> gamerEngine() async {
  final e = await freshEngine();
  await e.saveOnboarding(const OnboardingProfile(
    need: 'gaming',
    budgetMin: 6000000,
    budgetMax: 10000000,
    platform: 'amd',
  ));
  await e.record(UserEvent(
    type: UserEventType.addToDream,
    category: 'gpu',
    productName: 'AMD Radeon RX 7800 XT 16GB',
    price: 8500000,
    at: t0,
  ));
  await e.record(UserEvent(
    type: UserEventType.worthCheck,
    category: 'cpu',
    productName: 'AMD Ryzen 7 7800X3D',
    price: 6800000,
    at: t0,
  ));
  await e.record(UserEvent(
    type: UserEventType.viewDetail,
    category: 'gpu',
    productName: 'NVIDIA GeForce RTX 4070 12GB',
    price: 9500000,
    at: t0,
  ));
  return e;
}

Future<PersonalizationEngine> workerEngine() async {
  final e = await freshEngine();
  await e.saveOnboarding(const OnboardingProfile(
    need: 'kerja',
    budgetMin: 4000000,
    budgetMax: 6000000,
    platform: 'intel',
  ));
  await e.record(UserEvent(
    type: UserEventType.worthCheck,
    category: 'cpu',
    productName: 'Intel Core i5-12400F',
    price: 2100000,
    at: t0,
  ));
  await e.record(UserEvent(
    type: UserEventType.viewDetail,
    category: 'storage',
    productName: 'SSD Samsung 990 Pro NVMe 1TB',
    price: 1900000,
    at: t0,
  ));
  await e.record(UserEvent(
    type: UserEventType.viewDetail,
    category: 'cpu',
    productName: 'Intel Core i3-12100F',
    price: 1500000,
    at: t0,
  ));
  return e;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('bobot & decay', () {
    test('bobot mentah per tipe event', () async {
      final e = await freshEngine();
      await e.record(UserEvent(
        type: UserEventType.viewDetail,
        category: 'gpu',
        at: t0,
      ));
      expect(e.profile(now: t0).categoryWeights['gpu'], 1.0);

      final e2 = await freshEngine();
      await e2.record(UserEvent(
        type: UserEventType.addToDream,
        category: 'gpu',
        at: t0,
      ));
      expect(e2.profile(now: t0).categoryWeights['gpu'], 5.0);
    });

    test('half-life 14 hari: bobot jadi separuh, lalu seperempat', () async {
      final e = await freshEngine();
      await e.record(UserEvent(
        type: UserEventType.addToDream,
        category: 'gpu',
        at: t0,
      ));
      // 5 * 0.5^(14/14) = 2.5; 5 * 0.5^(28/14) = 1.25
      expect(
        e.profile(now: t0.add(const Duration(days: 14)))
            .categoryWeights['gpu'],
        closeTo(2.5, 0.01),
      );
      expect(
        e.profile(now: t0.add(const Duration(days: 28)))
            .categoryWeights['gpu'],
        closeTo(1.25, 0.01),
      );
    });

    test('pusat budget = median harga event', () async {
      final e = await gamerEngine();
      expect(e.profile(now: t0).budgetCenter, 8500000);
    });
  });

  group('onboarding', () {
    test('tersimpan, terbaca, dan jadi prior profil', () async {
      final e = await freshEngine();
      expect(await e.hasOnboarding(), isFalse);
      await e.saveOnboarding(const OnboardingProfile(
        need: 'gaming',
        budgetMin: 6000000,
        budgetMax: 10000000,
        platform: 'amd',
      ));
      expect(await e.hasOnboarding(), isTrue);
      final ob = await e.onboarding();
      expect(ob?.need, 'gaming');
      expect(ob?.platform, 'amd');

      final prof = e.profile();
      // Tanpa event berharga: pusat budget = tengah rentang onboarding.
      expect(prof.budgetCenter, 8000000);
      expect(prof.platformShares['amd'], closeTo(1.0, 0.001));
      expect(prof.categoryShares['gpu'], closeTo(0.45, 0.001));
    });

    test('prior onboarding ikut meluruh', () async {
      final e = await freshEngine();
      await e.saveOnboarding(const OnboardingProfile(
        need: 'gaming',
        budgetMin: 6000000,
        budgetMax: 10000000,
        platform: 'amd',
      ));
      // Massa prior 10 * 0.5 = 5 setelah 14 hari; gpu = 5 * 0.45 = 2.25.
      final prof = e.profile(now: DateTime.now().add(const Duration(days: 14)));
      expect(prof.categoryWeights['gpu'], closeTo(2.25, 0.1));
    });
  });

  group('ranking', () {
    test('dua profil berbeda -> urutan berbeda di katalog yang sama',
        () async {
      final gamer = await gamerEngine();
      final worker = await workerEngine();
      final gRank = gamer.rank(catalog, now: t0);
      final wRank = worker.rank(catalog, now: t0);

      expect(gRank.first.item.model, 'AMD Radeon RX 7800 XT 16GB');
      expect(wRank.first.item.model, isNot('AMD Radeon RX 7800 XT 16GB'));
      expect(
        gRank.map((s) => s.item.model).toList(),
        isNot(wRank.map((s) => s.item.model).toList()),
      );
      // Gamer menaruh GPU AMD di atas CPU Intel; pekerja sebaliknya.
      int idxOf(List<ScoredProduct> r, String m) =>
          r.indexWhere((s) => s.item.model == m);
      expect(
        idxOf(gRank, 'AMD Radeon RX 7800 XT 16GB') <
            idxOf(gRank, 'Intel Core i5-12400F'),
        isTrue,
      );
      expect(
        idxOf(wRank, 'Intel Core i5-12400F') <
            idxOf(wRank, 'AMD Radeon RX 7800 XT 16GB'),
        isTrue,
      );
    });

    test('formula: produk cocok semua dimensi > tidak cocok sama sekali',
        () async {
      final e = await gamerEngine();
      final ranked = e.rank(catalog, now: t0);
      final rx = ranked.firstWhere(
        (s) => s.item.model == 'AMD Radeon RX 7800 XT 16GB',
      );
      final i5 = ranked.firstWhere(
        (s) => s.item.model == 'Intel Core i5-12400F',
      );
      expect(rx.score, greaterThan(i5.score));
      expect(rx.score, greaterThan(0.6));
      expect(i5.score, lessThan(0.45));
      expect(rx.reason, 'Sering kamu lihat: GPU');
    });

    test('cold start: tanpa sinyal, urutan ditentukan worth', () async {
      final e = await freshEngine(worth: {
        'produk a': 0.1,
        'produk b': 0.9,
        'produk c': 0.5,
      });
      final items = [
        const CatalogItem(model: 'Produk A', price: 1000),
        const CatalogItem(model: 'Produk B', price: 1000),
        const CatalogItem(model: 'Produk C', price: 1000),
      ];
      final ranked = e.rank(items, now: t0);
      expect(
        ranked.map((s) => s.item.model).toList(),
        ['Produk B', 'Produk C', 'Produk A'],
      );
    });
  });

  group('showcase', () {
    test('deterministik dengan seed rng tetap', () async {
      final e = await gamerEngine();
      final a = e.showcase(catalog, limit: 4, rng: Random(42), now: t0);
      final b = e.showcase(catalog, limit: 4, rng: Random(42), now: t0);
      expect(a.map((i) => i.model).toList(), b.map((i) => i.model).toList());
      expect(a.length, 4);
    });

    test('cold start: urutan worth menurun tanpa acak', () async {
      final e = await freshEngine(worth: {
        'produk a': 0.1,
        'produk b': 0.9,
        'produk c': 0.5,
      });
      final items = [
        const CatalogItem(model: 'Produk A', price: 1000),
        const CatalogItem(model: 'Produk B', price: 1000),
        const CatalogItem(model: 'Produk C', price: 1000),
      ];
      final shown = e.showcase(items, limit: 2, rng: Random(7), now: t0);
      expect(shown.map((i) => i.model).toList(), ['Produk B', 'Produk C']);
    });
  });

  group('penyimpanan', () {
    test('cap 500 event ditegakkan (FIFO)', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final e = PersonalizationEngine(prefs);
      for (var i = 0; i < 505; i++) {
        await e.record(UserEvent(
          type: UserEventType.viewDetail,
          productName: 'Produk $i',
          at: t0,
        ));
      }
      final stored = jsonDecode(
        prefs.getString(PersonalizationEngine.eventsKey)!,
      ) as List<dynamic>;
      expect(stored.length, 500);
      expect((stored.first as Map)['productName'], 'Produk 5');
      expect((stored.last as Map)['productName'], 'Produk 504');
    });

    test('event bertahan lintas instance engine (persistensi)', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final e1 = PersonalizationEngine(prefs);
      await e1.record(UserEvent(
        type: UserEventType.worthCheck,
        category: 'cpu',
        at: t0,
      ));
      final e2 = PersonalizationEngine(prefs);
      expect(e2.profile(now: t0).categoryWeights['cpu'], 3.0);
    });
  });
}
