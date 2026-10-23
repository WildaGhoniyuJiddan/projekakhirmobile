import 'dart:math' as math;

import 'dataset.dart';
import 'relevance.dart';
import 'scoring.dart';

/// Port setia services/suggest.py (repo lama): autocomplete per section,
/// dua pool kondisi: BARU (katalog retail) dan gabungan (marketplace).
///
/// Perbedaan TERPAKSA oleh seam ListingsSource (dicatat, bukan disengaja):
/// query mentah SQL Python (mis. raw_listings kategori 'pc' tanpa batas
/// sumber) digantikan panggilan seam yang sudah ter-prefilter RPC
/// (rentang harga 50rb–150jt, sumber marketplace + komponen_retail,
/// condition != 'issue', urut scraped_at desc, limit 3000). Filter
/// in-memory Python di bawah ini tetap otoritatif & identik.

Set<String> _stokens(String? text) => RegExp(r'[a-z0-9]+')
    .allMatches((text ?? '').toLowerCase())
    .map((m) => m.group(0)!)
    .toSet();

/// Bentuk squash tanpa spasi/simbol: 'rx 6600' dan 'rx6600' sama.
String _ssq(String? text) =>
    (text ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

// Sinyal judulnya BUKAN komponen lepas (biasanya build PC).
final RegExp _notStandaloneRe = RegExp(
  r'\b(?:pc|rakitan|ryzen|core\s*i?\d?|intel|amd|rtx|gtx|vga|motherboard)\b|rx\s*\d{3,4}',
  caseSensitive: false,
);

const Map<String, List<String>> _sectionKeywords = {
  'ram': ['ram', 'memori', 'memory', 'sodimm', 'so-dimm'],
  'storage': ['ssd', 'hdd', 'nvme', 'harddisk', 'hard disk', 'm.2', 'm2 '],
};

// ponytail: kanonik RAM/storage manual (sama seperti Python).
const Map<String, List<String>> _canonical = {
  'ram': [
    'RAM DDR3 4GB', 'RAM DDR3 8GB', 'RAM DDR4 4GB', 'RAM DDR4 8GB',
    'RAM DDR4 16GB', 'RAM DDR4 32GB', 'RAM DDR5 8GB', 'RAM DDR5 16GB',
    'RAM DDR5 32GB', 'RAM Laptop DDR4 8GB',
  ],
  'storage': [
    'SSD SATA 240GB', 'SSD SATA 480GB', 'SSD SATA 1TB', 'SSD NVMe 256GB',
    'SSD NVMe 512GB', 'SSD NVMe 1TB', 'SSD NVMe 2TB',
    'HDD 1TB', 'HDD 2TB',
  ],
};

final RegExp _ramRe = RegExp(r'ram|memori|memory|ddr[345]', caseSensitive: false);
final RegExp _gbRe = RegExp(r'(\d{1,2})\s*gb\b', caseSensitive: false);
final RegExp _ssdRe = RegExp(r'\bssd\b|nvme|m\.?2\b', caseSensitive: false);
final RegExp _hddRe = RegExp(r'\bhdd\b|harddisk|hard disk', caseSensitive: false);
final RegExp _tbRe = RegExp(r'(\d)\s*tb\b', caseSensitive: false);

final Set<String> _sections = {..._canonical.keys, 'gpu', 'cpu', 'motherboard', 'laptop', 'pc'};
const int _maxLabel = 90;

int _matchScore(
  Set<String> labelTokens,
  String labelSq,
  Set<String> queryTokens,
  String querySq,
) {
  // 0 = tidak cocok; makin tinggi makin relevan.
  if (queryTokens.isEmpty) return 0;
  if (queryTokens.every(labelTokens.contains)) {
    return 40;
  } else if (querySq.isNotEmpty &&
      (labelSq.startsWith(querySq) || labelSq.contains(querySq))) {
    return 30; // squash match: 'rx660' cocok 'rx 6600'
  } else if (queryTokens
      .every((q) => labelTokens.any((t) => t.startsWith(q)))) {
    return 10; // prefix per-token
  }
  return 0;
}

/// Key dedupe tahan beda urutan kata & duplikat merek.
String _normKey(String label) {
  final toks = _stokens(label).toList()..sort();
  final joined = toks.join(' ');
  return joined.isNotEmpty ? joined : label.toUpperCase();
}

String? _canonicalRam(String title) {
  if (!_ramRe.hasMatch(title)) return null;
  final ddr = RegExp(r'ddr\s*([345])', caseSensitive: false).firstMatch(title);
  final laptop =
      RegExp(r'laptop|so-dimm|sodimm', caseSensitive: false).hasMatch(title);
  final gb = _gbRe.firstMatch(title);
  final String size;
  if (gb != null) {
    size = '${gb.group(1)}GB';
  } else {
    final tb = _tbRe.firstMatch(title);
    if (tb == null) return null;
    size = '${int.parse(tb.group(1)!) * 1024}GB';
  }
  if (ddr != null) {
    return laptop ? 'RAM Laptop DDR${ddr.group(1)} $size' : 'RAM DDR${ddr.group(1)} $size';
  }
  return laptop ? 'RAM Laptop $size' : null;
}

String? _canonicalStorage(String title) {
  final tb = _tbRe.firstMatch(title);
  final gbMatch = _gbRe.firstMatch(title);
  final size = tb != null
      ? '${tb.group(1)}TB'
      : (gbMatch != null ? '${gbMatch.group(1)}GB' : null);
  if (size == null) return null;
  if (_hddRe.hasMatch(title)) return 'HDD $size';
  if (_ssdRe.hasMatch(title)) {
    final nvme = RegExp(r'nvme', caseSensitive: false).hasMatch(title);
    final sata = RegExp(r'sata', caseSensitive: false).hasMatch(title);
    if (nvme && sata) return 'SSD NVMe $size'; // NVMe spesifik -> prioritas
    if (nvme) return 'SSD NVMe $size';
    if (sata) return 'SSD SATA $size';
    return 'SSD $size';
  }
  return null;
}

class _Cand {
  _Cand(this.rank, this.popularity, this.price, this.label);
  (int, int) rank;
  int popularity;
  double? price;
  String label;
}

int _rankCompare(_Cand a, _Cand b, {required bool withPopularity}) {
  // Urutan Python: sorted(..., key=(rank, popularity, -len), reverse=True)
  var c = b.rank.$1.compareTo(a.rank.$1);
  if (c != 0) return c;
  c = b.rank.$2.compareTo(a.rank.$2);
  if (c != 0) return c;
  if (withPopularity) {
    c = b.popularity.compareTo(a.popularity);
    if (c != 0) return c;
  }
  // -len(label) dibalik -> label lebih pendek lebih dulu.
  return a.label.length.compareTo(b.label.length);
}

class SuggestEngine {
  const SuggestEngine(this.data, this.listings);

  final BenchmarkData data;
  final ListingsSource listings;

  /// Median harga per bentuk kanonik RAM/storage dari judul listing real.
  Future<Map<String, List<int>>> _marketPrices(String section) async {
    final out = <String, List<int>>{};
    if (!_canonical.containsKey(section)) return out;
    final canonFn = section == 'ram' ? _canonicalRam : _canonicalStorage;
    final rows = await listings.pcListings(categories: ['pc']);
    var count = 0;
    for (final row in rows) {
      if (count >= 1200) break;
      if (row.price <= 50000) continue;
      count++;
      final title = row.title;
      if (_notStandaloneRe.hasMatch(title)) continue;
      final key = canonFn(title);
      if (key != null) {
        out.putIfAbsent(key, () => []).add(row.price);
      }
    }
    return out;
  }

  /// Pool saran kondisi BARU: katalog retail (harga retail IDR real).
  List<Map<String, Object?>> _retailCandidates(
    String section,
    Set<String> queryTokens,
    String querySq,
  ) {
    final retail = data.retail;
    final catalog = <String, num>{};
    final sectionsToCheck = (section == 'pc')
        ? const ['gpu', 'cpu', 'motherboard', 'ram', 'storage']
        : [section];

    for (final s in sectionsToCheck) {
      if (s == 'gpu' || s == 'cpu' || s == 'motherboard') {
        final list = retail[s];
        if (list is List) {
          for (final prod in list) {
            if (prod is! Map) continue;
            final model = (prod['model'] as String? ?? '').trim();
            final price = prod['price'];
            if (model.isNotEmpty && price is int) {
              catalog[model.length > 90 ? model.substring(0, 90) : model] =
                  price;
            }
          }
        }
      } else if (s == 'ram') {
        final m = retail['ram_canonical'];
        if (m is Map) {
          m.forEach((k, v) {
            if (v is num) catalog[k.toString()] = v;
          });
        }
      } else if (s == 'storage') {
        final m = retail['storage_canonical'];
        if (m is Map) {
          m.forEach((k, v) {
            if (v is num) catalog[k.toString()] = v;
          });
        }
      }
    }

    final candidates = <String, _Cand>{};

    void add(String labelRaw, double? price) {
      final label = labelRaw
          .split(RegExp(r'\s+'))
          .where((s) => s.isNotEmpty)
          .join(' ');
      if (label.isEmpty) return;
      final score =
          _matchScore(_stokens(label), _ssq(label), queryTokens, querySq);
      if (score <= 0 && queryTokens.isNotEmpty) return;
      final key = _normKey(label);
      final rank = (score, 0);
      final prev = candidates[key];
      if (prev == null ||
          rank.$1 > prev.rank.$1 ||
          (rank.$1 == prev.rank.$1 && rank.$2 > prev.rank.$2)) {
        candidates[key] = _Cand(rank, 0, price, label);
      }
    }

    for (final e in catalog.entries) {
      add(e.key, e.value.toDouble());
    }
    final ranked = candidates.values.toList();
    stableSort(ranked, (a, b) => _rankCompare(a, b, withPopularity: false));
    return [
      for (final c in ranked.take(12))
        <String, Object?>{
          'label': c.label,
          'samples': 0,
          'price': (c.price == null || c.price == 0)
              ? null
              : pyRoundInt(c.price!),
        },
    ];
  }

  /// Port suggest_components().
  Future<List<Map<String, Object?>>> suggestComponents({
    required String section,
    required String q,
    int limit = 8,
    String? condition,
  }) async {
    final sec = section.toLowerCase();
    if (!_sections.contains(sec)) return [];
    final qlow = (q)
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .join(' ');
    var cond = (condition ?? '').toLowerCase();
    if (cond.isEmpty) cond = '';
    final condNorm = cond.isEmpty ? null : cond;

    final detectedType = componentTypeFromQuery(qlow);
    final effectiveSec = (sec == 'pc') ? (detectedType ?? 'pc') : sec;

    // Pool BARU: murni katalog retail — tanpa listing marketplace.
    if (condNorm == 'baru') {
      final retail =
          _retailCandidates(effectiveSec, _stokens(qlow), _ssq(qlow));
      final sliced = retail.take(limit).toList();
      if (sliced.isNotEmpty) return sliced;
      // ponytail: katalog retail belum ada utk section ini -> fallback
      // ke pool gabungan (perilaku Python sama).
    }

    final queryTokens = _stokens(qlow);
    final querySq = _ssq(qlow);
    final candidates = <String, _Cand>{};

    void add(String labelRaw, int popularity, double? price, {int bonus = 0}) {
      var label = labelRaw
          .split(RegExp(r'\s+'))
          .where((s) => s.isNotEmpty)
          .join(' ');
      if (label.isEmpty || label.toLowerCase().contains('http')) return;
      final low = label.toLowerCase();
      // Section RAM/storage: saran judul harus benar-benar soal RAM/SSD.
      final keywords = _sectionKeywords[effectiveSec];
      if (keywords != null) {
        if (!keywords.any((k) => low.contains(k)) ||
            _notStandaloneRe.hasMatch(low)) {
          return;
        }
      } else if (effectiveSec == 'gpu' &&
          RegExp(r'\b(?:frame|bracket|riser|backplate|support)\b')
              .hasMatch(low)) {
        return; // aksesori VGA, bukan kartunya
      }
      // Filter relevansi seragam utk SEMUA pool.
      if (queryTokens.isNotEmpty &&
          !isRelevantPcListing(qlow, low, effectiveSec)) {
        return;
      }
      final key = _normKey(label);
      final score =
          _matchScore(_stokens(label), _ssq(label), queryTokens, querySq);
      if (score <= 0 && queryTokens.isNotEmpty) return;
      if (label.length > _maxLabel) {
        final head = label.substring(0, _maxLabel);
        final idx = head.lastIndexOf(' ');
        label = '${idx >= 0 ? head.substring(0, idx) : head}…';
      }
      final rank = (score + bonus, popularity);
      final prev = candidates[key];
      if (prev == null ||
          rank.$1 > prev.rank.$1 ||
          (rank.$1 == prev.rank.$1 && rank.$2 > prev.rank.$2)) {
        candidates[key] = _Cand(rank, popularity, price, label);
      }
    }

    // 1) Kanonik RAM/storage + median harga real dari listing.
    final canonicalSecs = (sec == 'pc')
        ? (detectedType != null && _canonical.containsKey(detectedType)
            ? [detectedType]
            : (detectedType == null
                ? const ['ram', 'storage']
                : const <String>[]))
        : (_canonical.containsKey(sec) ? [sec] : const <String>[]);
    for (final csec in canonicalSecs) {
      final market = await _marketPrices(csec);
      for (final label in _canonical[csec] ?? const <String>[]) {
        final prices = market[label] ?? const <int>[];
        add(
          label,
          math.max(prices.length, 20),
          prices.isEmpty ? null : medianOf(prices),
          bonus: 15,
        );
      }
    }

    // 2) Katalog komponen (model bersih hasil agregasi).
    if (sec == 'gpu' || sec == 'cpu' || sec == 'motherboard' || sec == 'pc') {
      final queryTokensParam = (sec == 'pc' && detectedType != null)
          ? [detectedType]
          : (sec == 'pc' ? const <String>[] : [sec]);
      final rows = await listings.pcComponents(tokens: queryTokensParam);
      final collapsed = <String, (int, double?)>{};
      for (final row in rows) {
        final typeVal = row['component_type'];
        if (typeVal != null && sec != 'pc' && typeVal != sec) continue;
        if (typeVal != null &&
            sec == 'pc' &&
            detectedType != null &&
            typeVal != detectedType) {
          continue;
        }
        final model = (row['model'] as String? ?? '').toUpperCase();
        if (model.isEmpty) continue;
        final samples = (row['sample_count'] as num?)?.toInt() ?? 0;
        final price = (row['avg_price'] as num?)?.toDouble();
        final prev = collapsed[model];
        if (prev == null || samples > prev.$1) {
          collapsed[model] = (samples, price);
        }
      }
      final signatures = <(int, int), int>{};
      for (final v in collapsed.values) {
        final sig = (v.$1, v.$2?.toInt() ?? 0);
        signatures[sig] = (signatures[sig] ?? 0) + 1;
      }
      for (final e in collapsed.entries) {
        final samples = e.value.$1;
        final price = e.value.$2;
        if ((signatures[(samples, price?.toInt() ?? 0)] ?? 0) > 3) {
          continue; // baris artefak scraper, bukan produk nyata
        }
        add(e.key, math.min(samples, 50), price, bonus: 15);
      }
    }

    // 3) Katalog laptop.
    if (sec == 'laptop') {
      final rows = await listings.laptopUnits(tokens: const []);
      var count = 0;
      for (final row in rows) {
        if (count >= 400) break;
        final price = (row['price'] as num?)?.toInt() ?? 0;
        if (price <= 100000) continue;
        count++;
        final brand = row['brand'] as String? ?? '';
        final model = row['model'] as String? ?? '';
        final brandWords = brand
            .toLowerCase()
            .split(RegExp(r'\s+'))
            .where((s) => s.isNotEmpty)
            .toSet();
        final trimmed = model
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty && !brandWords.contains(w.toLowerCase()))
            .join(' ');
        final label = [brand, trimmed.isNotEmpty ? trimmed : model]
            .where((s) => s.isNotEmpty)
            .join(' ');
        // Junk scraper (URL/markdown) & judul non-laptop jangan masuk pool.
        if (label.toLowerCase().contains('http') ||
            !isRelevantPcListing(label, label, 'laptop')) {
          continue;
        }
        add(label, 1, price.toDouble());
      }
    }

    // 4) Judul listing real — bahasa pasar apa adanya, plus harganya.
    if (queryTokens.isNotEmpty) {
      final rows = await listings.pcListings(
        categories: [sec == 'laptop' ? 'laptop' : 'pc'],
      );
      var count = 0;
      for (final row in rows) {
        if (count >= 600) break;
        if (row.price <= 50000) continue;
        count++;
        final title = row.title;
        if (!isRelevantPcListing(title, title, effectiveSec)) continue;
        add(title, 1, row.price.toDouble());
      }
    }

    // 5) Basis katalog retail terverifikasi selalu disertakan
    final retailCands =
        _retailCandidates(effectiveSec, queryTokens, querySq);
    for (final r in retailCands) {
      final lbl = r['label'] as String?;
      final prc = (r['price'] as num?)?.toDouble();
      if (lbl != null) add(lbl, 10, prc, bonus: 10);
    }

    final ranked = candidates.values.toList();
    stableSort(ranked, (a, b) => _rankCompare(a, b, withPopularity: true));
    return [
      for (final c in ranked.take(limit))
        <String, Object?>{
          'label': c.label,
          'samples': c.popularity,
          'price': (c.price == null || c.price == 0)
              ? null
              : pyRoundInt(c.price!),
        },
    ];
  }
}
