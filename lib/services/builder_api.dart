import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/rupiah.dart';
import '../models/builder_models.dart';
import 'local_catalog.dart';

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
      final items = sectionItems[sec]!;

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

      final affordable = items.where((e) => e.price <= maxAllowed).toList();
      if (affordable.isEmpty) {
        items.sort((a, b) => a.price.compareTo(b.price));
        chosen[sec] = items.first;
        remainingBudget -= items.first.price;
        continue;
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
          pool = underTarget.take(5).toList();
        }
      } else {
        // Jika targetPrice lebih kecil dari item termurah yang tersedia,
        // ambil item-item termurah yang masih affordable (<= maxAllowed)
        affordable.sort((a, b) => a.price.compareTo(b.price));
        final lowestPrice = affordable.first.price;
        final threshold = (lowestPrice * 1.30).toInt();
        pool = affordable.where((e) => e.price <= threshold && e.price <= maxAllowed).toList();
        if (pool.length < 3) {
          pool = affordable.take(5).toList();
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
    'psu': 0.12,
    'gpu': 0.12,
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
  'office': ['cpu', 'ram', 'storage', 'psu', 'gpu'],
  'editing': ['cpu', 'gpu', 'ram', 'storage', 'psu'],
};

const _psuEstimates = [
  CatalogItem(model: 'PSU 350W Bawaan Casing (estimasi)', price: 120000),
  CatalogItem(model: 'PSU 400W Standar (estimasi)', price: 150000),
  CatalogItem(model: 'PSU 450W 80+ (estimasi)', price: 400000),
  CatalogItem(model: 'PSU 500W 80+ Bronze (estimasi)', price: 550000),
  CatalogItem(model: 'PSU 550W 80+ Bronze (estimasi)', price: 750000),
  CatalogItem(model: 'PSU 650W 80+ Bronze (estimasi)', price: 950000),
  CatalogItem(model: 'PSU 750W 80+ Gold (estimasi)', price: 1350000),
  CatalogItem(model: 'PSU 850W 80+ Gold (estimasi)', price: 1850000),
];
