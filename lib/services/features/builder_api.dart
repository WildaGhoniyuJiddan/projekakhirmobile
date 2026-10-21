import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../utils/rupiah.dart';
import '../../models/builder_models.dart';
import '../data/local_catalog.dart';

final builderApiProvider = Provider<BuilderApi>((ref) => BuilderApi());

/// Random builder — 100% lokal dari katalog bundled.
/// Mengalokasikan komponen secara cerdas & acak sesuai use-case
/// serta menjamin total harga tidak melebihi budget yang diinput pengguna.
class BuilderApi {
  BuilderApi({Random? random}) : _random = random ?? Random();

  final Random _random;
  RandomBuild? _lastBuild;

  Future<RandomBuild> randomBuild({
    required int budget,
    required String useCase,
    Random? rng,
  }) async {
    final cat = await LocalCatalog.load();
    final random = rng ?? _random;

    final normalizedUseCase = useCase.toLowerCase();
    final alloc =
        _allocations[normalizedUseCase] ?? _allocations['gaming']!;
    final order =
        _pickOrders[normalizedUseCase] ?? _pickOrders['gaming']!;

    // Siapkan pool per seksi
    final sectionItems = <String, List<CatalogItem>>{
      'cpu': (cat['cpu'] ?? const <CatalogItem>[]).where((e) => e.price > 0).toList(),
      'gpu': (cat['gpu'] ?? const <CatalogItem>[]).where((e) => e.price > 0).toList(),
      'ram': (cat['ram'] ?? const <CatalogItem>[]).where((e) => e.price > 0).toList(),
      'storage': (cat['storage'] ?? const <CatalogItem>[]).where((e) => e.price > 0).toList(),
      'psu': _psuEstimates,
    };

    // Hitung harga minimum untuk setiap komponen
    final minPrices = <String, int>{};
    for (final sec in order) {
      final items = sectionItems[sec] ?? const <CatalogItem>[];
      if (items.isEmpty) {
        throw BuilderException('Katalog komponen $sec tidak tersedia.');
      }
      minPrices[sec] = items.map((e) => e.price).reduce(min);
    }

    final totalMinPrice = minPrices.values.reduce((a, b) => a + b);
    if (budget < totalMinPrice) {
      throw BuilderException(
        'Budget minimal untuk rakit PC adalah ${formatRupiah(totalMinPrice)}.',
      );
    }

    int remainingBudget = budget;
    final chosen = <String, CatalogItem>{};

    for (int i = 0; i < order.length; i++) {
      final sec = order[i];
      var items = sectionItems[sec]!;

      // Filter khusus PSU: sesuaikan wattage dengan GPU, CPU, dan Budget tier
      if (sec == 'psu') {
        final minWatt = calculateMinPsuWattage(
          gpu: chosen['gpu'],
          cpu: chosen['cpu'],
          totalBudget: budget,
        );
        final matchingWatt = items
            .where((e) => extractPsuWattage(e.model) >= minWatt)
            .toList();
        if (matchingWatt.isNotEmpty) {
          items = matchingWatt;
        }
      }

      // Hitung sisa budget yang harus disisihkan untuk komponen-komponen berikutnya
      int remainingMin = 0;
      for (int j = i + 1; j < order.length; j++) {
        remainingMin += minPrices[order[j]]!;
      }

      // Komponen saat ini tidak boleh melebihi sisa budget dikurangi biaya minimum sisa komponen
      final maxAllowed = remainingBudget - remainingMin;

      // Bobot proporsional terhadap sisa komponen
      double totalWeight = 0;
      for (int j = i; j < order.length; j++) {
        totalWeight += alloc[order[j]] ?? 0.1;
      }

      final share = (alloc[sec] ?? 0.1) / (totalWeight > 0 ? totalWeight : 1.0);
      final targetPrice = (remainingBudget * share).toInt().clamp(minPrices[sec]!, maxAllowed);

      var affordable = items.where((e) => e.price <= maxAllowed).toList();
      if (affordable.isEmpty) {
        // Fallback ke seluruh item seksi jika filter spesifik (seperti PSU min watt)
        // tidak muat di sisa budget (misal budget sangat ketat)
        affordable = sectionItems[sec]!.where((e) => e.price <= maxAllowed).toList();
        if (affordable.isEmpty) {
          final sortedAll = [...sectionItems[sec]!]..sort((a, b) => a.price.compareTo(b.price));
          chosen[sec] = sortedAll.first;
          remainingBudget -= sortedAll.first.price;
          continue;
        }
      }

      // Filter kandidat terbaik dekat targetPrice
      final underTarget = affordable.where((e) => e.price <= targetPrice).toList();
      List<CatalogItem> pool;
      if (underTarget.isNotEmpty) {
        underTarget.sort((a, b) => b.price.compareTo(a.price));
        final topPrice = underTarget.first.price;
        final threshold = (topPrice * 0.70).toInt();
        pool = underTarget.where((e) => e.price >= threshold).toList();
        if (pool.length < 3) {
          pool = underTarget.take(3).toList();
        }
      } else {
        // Jika targetPrice lebih kecil dari item termurah yang tersedia,
        // ambil item-item termurah yang masih affordable (<= maxAllowed)
        affordable.sort((a, b) => a.price.compareTo(b.price));
        final lowestPrice = affordable.first.price;
        final threshold = (lowestPrice * 1.30).toInt();
        pool = affordable.where((e) => e.price <= threshold && e.price <= maxAllowed).toList();
        if (pool.length < 3) {
          pool = affordable.take(3).toList();
        }
      }

      final picked = _pickDifferent(pool, _previousPart(sec), random);
      chosen[sec] = picked;
      remainingBudget -= picked.price;
    }

    BuildComponent part(CatalogItem e) =>
        BuildComponent(name: e.model, price: e.price);

    final cpu = chosen['cpu']!;
    final gpu = chosen['gpu']!;
    final ram = chosen['ram']!;
    final ssd = chosen['storage']!;
    final psu = chosen['psu']!;

    final total = cpu.price + gpu.price + ram.price + ssd.price + psu.price;
    final build = RandomBuild(
      cpu: part(cpu),
      gpu: part(gpu),
      ram: part(ram),
      ssd: part(ssd),
      psu: part(psu),
      total: total,
      budget: budget,
    );
    _lastBuild = build;
    return build;
  }

  /// Ekstraksi kapasitas daya (Watt) dari nama/model PSU
  static int extractPsuWattage(String model) {
    final match = RegExp(r'(\d{3,4})\s*W', caseSensitive: false).firstMatch(model);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 500;
    }
    return 500;
  }

  /// Menghitung kebutuhan daya minimal PSU secara realistis berdasarkan
  /// GPU, CPU, dan tier budget keseluruhan.
  static int calculateMinPsuWattage({
    CatalogItem? gpu,
    CatalogItem? cpu,
    required int totalBudget,
  }) {
    int minWatt = 450;
    final g = (gpu?.model ?? '').toUpperCase();
    final c = (cpu?.model ?? '').toUpperCase();

    // 1. Kebutuhan daya berdasarkan GPU
    if (g.contains('5090') ||
        g.contains('4090') ||
        g.contains('3090') ||
        g.contains('7900 XTX') ||
        g.contains('PRO 6000') ||
        g.contains('PRO 5000')) {
      minWatt = max(minWatt, 1000);
    } else if (g.contains('5080') ||
        g.contains('4080') ||
        g.contains('7900 XT') ||
        g.contains('7900 GRE') ||
        g.contains('6950 XT') ||
        g.contains('6900 XT')) {
      minWatt = max(minWatt, 850);
    } else if (g.contains('5070 TI') ||
        g.contains('4070 TI') ||
        g.contains('3080') ||
        g.contains('7800 XT') ||
        g.contains('6800 XT')) {
      minWatt = max(minWatt, 750);
    } else if (g.contains('5070') ||
        g.contains('4070') ||
        g.contains('3070') ||
        g.contains('7700 XT') ||
        g.contains('6750 XT') ||
        g.contains('6700 XT')) {
      minWatt = max(minWatt, 650);
    } else if (g.contains('4060 TI') ||
        g.contains('3060 TI') ||
        g.contains('7600 XT') ||
        g.contains('6700') ||
        g.contains('A770') ||
        g.contains('A750')) {
      minWatt = max(minWatt, 550);
    } else if (g.contains('4060') ||
        g.contains('3060') ||
        g.contains('3050') ||
        g.contains('1660') ||
        g.contains('7600') ||
        g.contains('6600')) {
      minWatt = max(minWatt, 500);
    }

    // 2. Kebutuhan daya tambahan untuk CPU HEDT/Server/High-end
    if (c.contains('THREADRIPPER') || c.contains('EPYC')) {
      minWatt = max(minWatt, 1000);
    } else if (c.contains('I9') ||
        c.contains('RYZEN 9') ||
        c.contains('R9')) {
      minWatt = max(minWatt, minWatt >= 750 ? 850 : 750);
    }

    // 3. Batas minimum kewajaran perakitan PC nyata berdasarkan budget tier
    if (totalBudget >= 75000000) {
      minWatt = max(minWatt, 1000);
    } else if (totalBudget >= 45000000) {
      minWatt = max(minWatt, 850);
    } else if (totalBudget >= 25000000) {
      minWatt = max(minWatt, 750);
    } else if (totalBudget >= 15000000) {
      minWatt = max(minWatt, 650);
    } else if (totalBudget >= 9000000) {
      minWatt = max(minWatt, 550);
    }

    return minWatt;
  }

  BuildComponent? _previousPart(String section) {
    final previous = _lastBuild;
    if (previous == null) return null;
    return switch (section) {
      'cpu' => previous.cpu,
      'gpu' => previous.gpu,
      'ram' => previous.ram,
      'storage' => previous.ssd,
      'psu' => previous.psu,
      _ => null,
    };
  }

  CatalogItem _pickDifferent(
    List<CatalogItem> candidates,
    BuildComponent? previous,
    Random random,
  ) {
    final alternatives = previous == null
        ? candidates
        : candidates
            .where((item) =>
                item.model != previous.name || item.price != previous.price)
            .toList();
    final pool = alternatives.isEmpty ? candidates : alternatives;
    return pool[random.nextInt(pool.length)];
  }
}

const _allocations = {
  'gaming': {
    'gpu': 0.44,
    'cpu': 0.24,
    'ram': 0.12,
    'storage': 0.12,
    'psu': 0.08,
  },
  'office': {
    'cpu': 0.34,
    'ram': 0.22,
    'storage': 0.20,
    'gpu': 0.12,
    'psu': 0.12,
  },
  'editing': {
    'cpu': 0.30,
    'gpu': 0.30,
    'ram': 0.18,
    'storage': 0.14,
    'psu': 0.08,
  },
};

const _pickOrders = {
  'gaming': ['gpu', 'cpu', 'ram', 'storage', 'psu'],
  'office': ['cpu', 'ram', 'storage', 'gpu', 'psu'],
  'editing': ['cpu', 'gpu', 'ram', 'storage', 'psu'],
};

const _psuEstimates = [
  CatalogItem(model: 'PSU 350W Bawaan Casing (estimasi)', price: 120000),
  CatalogItem(model: 'PSU 400W Standar (estimasi)', price: 180000),
  CatalogItem(model: 'PSU 450W 80+ White (estimasi)', price: 400000),
  CatalogItem(model: 'PSU 500W 80+ Bronze (estimasi)', price: 550000),
  CatalogItem(model: 'PSU 550W 80+ Bronze (estimasi)', price: 750000),
  CatalogItem(model: 'PSU 650W 80+ Bronze (estimasi)', price: 950000),
  CatalogItem(model: 'PSU 650W 80+ Gold (estimasi)', price: 1250000),
  CatalogItem(model: 'PSU 750W 80+ Bronze (estimasi)', price: 1150000),
  CatalogItem(model: 'PSU 750W 80+ Gold (estimasi)', price: 1550000),
  CatalogItem(model: 'PSU 850W 80+ Gold Fully Modular (estimasi)', price: 1950000),
  CatalogItem(model: 'PSU 850W 80+ Platinum ATX 3.0 (estimasi)', price: 2550000),
  CatalogItem(model: 'PSU 1000W 80+ Gold ATX 3.0 PCIe 5.0 (estimasi)', price: 3200000),
  CatalogItem(model: 'PSU 1000W 80+ Platinum ATX 3.0 (estimasi)', price: 3950000),
  CatalogItem(model: 'PSU 1200W 80+ Platinum ATX 3.0 (estimasi)', price: 5200000),
  CatalogItem(model: 'PSU 1300W 80+ Platinum PCIe 5.0 (estimasi)', price: 6300000),
  CatalogItem(model: 'PSU 1600W 80+ Titanium ATX 3.0 (estimasi)', price: 8500000),
];
