import 'dart:math';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:worthbang/services/local_catalog.dart';
import 'package:worthbang/services/builder_api.dart';
import 'package:worthbang/models/builder_models.dart';
import 'package:worthbang/services/shake_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RandomBuild.fromJson (kontrak B6)', () {
    test('parse response lengkap', () {
      final b = RandomBuild.fromJson({
        'cpu': {'name': 'Ryzen 5 5600', 'price': 1850000},
        'gpu': {'name': 'RTX 4060 8GB', 'price': 4790000},
        'ram': {'name': 'TeamGroup 2x8GB', 'price': 650000},
        'ssd': {'name': 'ADATA 512GB', 'price': 550000},
        'psu': {'name': 'MSI 550W', 'price': 750000},
        'total': 8590000,
        'budget': 10000000,
      });
      expect(b.cpu.name, 'Ryzen 5 5600');
      expect(b.parts.length, 5);
      expect(b.total, 8590000);
      expect(b.total <= b.budget, isTrue);
    });
  });

  group('BuilderApi', () {
    test('extractPsuWattage parses wattages accurately', () {
      expect(BuilderApi.extractPsuWattage('PSU 350W Bawaan Casing'), 350);
      expect(BuilderApi.extractPsuWattage('PSU 650W 80+ Bronze'), 650);
      expect(BuilderApi.extractPsuWattage('PSU 750W 80+ Gold'), 750);
      expect(BuilderApi.extractPsuWattage('PSU 850W 80+ Gold Fully Modular'), 850);
      expect(BuilderApi.extractPsuWattage('PSU 1000W 80+ Platinum ATX 3.0'), 1000);
      expect(BuilderApi.extractPsuWattage('PSU 1600W 80+ Titanium ATX 3.0'), 1600);
      expect(BuilderApi.extractPsuWattage('PSU Standar Polos'), 500);
    });

    test('calculateMinPsuWattage matches GPU, CPU, and budget tier requirements', () {
      // GPU flagship
      expect(
        BuilderApi.calculateMinPsuWattage(
          gpu: const CatalogItem(model: 'MSI GeForce RTX 5090 32GB', price: 95000000),
          totalBudget: 100000000,
        ),
        greaterThanOrEqualTo(1000),
      );
      expect(
        BuilderApi.calculateMinPsuWattage(
          gpu: const CatalogItem(model: 'Asus ROG Strix RTX 4090 24GB', price: 38000000),
          totalBudget: 50000000,
        ),
        greaterThanOrEqualTo(1000),
      );

      // GPU high-end
      expect(
        BuilderApi.calculateMinPsuWattage(
          gpu: const CatalogItem(model: 'MSI GeForce RTX 4080 Super', price: 21000000),
          totalBudget: 35000000,
        ),
        greaterThanOrEqualTo(850),
      );

      // CPU HEDT / Threadripper
      expect(
        BuilderApi.calculateMinPsuWattage(
          cpu: const CatalogItem(model: 'AMD Ryzen Threadripper PRO 7995WX', price: 180000000),
          totalBudget: 100000000,
        ),
        greaterThanOrEqualTo(1000),
      );

      // Budget 100 juta selalu memiliki floor min 1000W
      expect(
        BuilderApi.calculateMinPsuWattage(totalBudget: 100000000),
        greaterThanOrEqualTo(1000),
      );

      // Budget 50 juta memiliki floor min 850W
      expect(
        BuilderApi.calculateMinPsuWattage(totalBudget: 50000000),
        greaterThanOrEqualTo(850),
      );
    });

    test('budget 100 juta memilih PSU realistis (>= 1000W, tidak pernah 650W)', () async {
      final api = BuilderApi(random: Random(12345));
      for (final useCase in ['gaming', 'editing', 'office']) {
        for (var i = 0; i < 10; i++) {
          final build = await api.randomBuild(
            budget: 100000000,
            useCase: useCase,
          );
          expect(build.total, lessThanOrEqualTo(100000000));
          expect(build.parts, hasLength(5));

          final psuWatt = BuilderApi.extractPsuWattage(build.psu.name);
          expect(
            psuWatt,
            greaterThanOrEqualTo(1000),
            reason: 'PSU ${build.psu.name} terlalu kecil untuk build Rp 100.000.000 ($useCase run $i)',
          );
          expect(
            psuWatt > 650,
            isTrue,
            reason: 'PSU tidak boleh 650W ke bawah pada budget 100 juta',
          );
        }
      }
    });

    test(
      'randomBuild varies on each generation and stays within budget',
      () async {
        final api = BuilderApi(random: Random(42));
        for (final useCase in ['gaming', 'office', 'editing']) {
          RandomBuild? previous;
          for (var i = 0; i < 10; i++) {
            final build = await api.randomBuild(
              budget: 10000000,
              useCase: useCase,
            );
            expect(build.parts, hasLength(5));
            expect(build.budget, 10000000);
            expect(build.total, lessThanOrEqualTo(build.budget));
            if (previous != null) {
              expect(_signature(build), isNot(_signature(previous)));
            }
            previous = build;
          }
        }
      },
    );

    test('budget 1 juta tidak melebihi nominal 1 juta (fix issue)', () async {
      final api = BuilderApi();
      final build = await api.randomBuild(budget: 1000000, useCase: 'gaming');
      expect(build.budget, 1000000);
      expect(build.total, lessThanOrEqualTo(1000000));
      expect(build.gpu.price, lessThan(1000000));
      expect(build.cpu.price, lessThan(1000000));
      expect(build.ram.price, lessThan(1000000));
      expect(build.ssd.price, lessThan(1000000));
      expect(build.psu.price, lessThan(1000000));
      expect(
        build.total,
        equals(build.cpu.price +
            build.gpu.price +
            build.ram.price +
            build.ssd.price +
            build.psu.price),
      );
    });

    test('budget 1 juta untuk semua use case <= 1 juta', () async {
      final api = BuilderApi();
      for (final uc in ['gaming', 'office', 'editing']) {
        final build = await api.randomBuild(budget: 1000000, useCase: uc);
        expect(build.total, lessThanOrEqualTo(1000000), reason: 'Failed for $uc');
      }
    });

    test('budget terlalu kecil melempar BuilderException', () async {
      final api = BuilderApi();
      expect(
        () => api.randomBuild(budget: 500000, useCase: 'gaming'),
        throwsA(isA<BuilderException>()),
      );
    });
  });

  group('ShakeDetector', () {
    test('goyangan kuat memicu callback', () async {
      final ctrl = StreamController<AccelerometerEvent>();
      var shakes = 0;
      final d = ShakeDetector(
        stream: ctrl.stream,
        threshold: 5.0,
        cooldown: Duration.zero,
      );
      d.start(() => shakes++);

      ctrl.add(AccelerometerEvent(0, 0, 9.8, DateTime.now()));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(shakes, 0); // sampel pertama = baseline

      // Gerakan kecil: di bawah threshold.
      ctrl.add(AccelerometerEvent(0.5, 0.3, 9.9, DateTime.now()));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(shakes, 0);

      // Goyangan kuat.
      ctrl.add(AccelerometerEvent(12, -8, 2, DateTime.now()));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(shakes, 1);

      d.stop();
      await ctrl.close();
    });

    test('cooldown menahan trigger ganda', () async {
      final ctrl = StreamController<AccelerometerEvent>();
      var shakes = 0;
      final d = ShakeDetector(
        stream: ctrl.stream,
        threshold: 5.0,
        cooldown: const Duration(seconds: 30),
      );
      d.start(() => shakes++);

      ctrl.add(AccelerometerEvent(0, 0, 9.8, DateTime.now()));
      ctrl.add(AccelerometerEvent(12, -8, 2, DateTime.now()));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      ctrl.add(AccelerometerEvent(-12, 8, 18, DateTime.now()));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(shakes, 1);

      d.stop();
      await ctrl.close();
    });
  });
}

String _signature(RandomBuild build) => [
  build.cpu,
  build.gpu,
  build.ram,
  build.ssd,
  build.psu,
].map((part) => '${part.name}:${part.price}').join('|');
