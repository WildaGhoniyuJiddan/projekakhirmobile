import 'dart:math' as math;

import '../../models/bundle_models.dart';
import 'benchmark.dart';
import 'dataset.dart';
import 'relevance.dart';
import 'scoring.dart';

/// Port setia services/analysis.py + endpoint analyze-bundle di
/// app/main.py (repo lama). Mesin analisis harga: pembanding listing,
/// skor kelayakan, tier benchmark, alternatif, bundle.
///
/// Penyimpangan TERPAKSA oleh seam ListingsSource (dicatat):
/// - Query SQL mentah Python digantikan seam: prefilter RPC
///   (match_listings) menangani rentang harga/sumber/kondisi/ilike;
///   penyaringan in-memory di sini identik & otoritatif.
/// - Fallback per-sumber Python digabung jadi satu panggilan seam
///   (seam tak bisa memfilter per sumber); dedupe pakai kunci komposit
///   karena ListingRow tak punya id.
/// - Freshness per-sumber (tabel scrape_runs) tak tersedia di seam;
///   label/umur dihitung dari listing terbaru global
///   (ListingsSource.latestScrapedAt), primarySource tetap sumber
///   dominan pembanding seperti Python.

// ponytail: harga BARU referensi (USD street) -> IDR, sama seperti Python.
const int usdToIdr = 16500;
const double retailMarkup = 1.10;
// get_settings().stale_after_hours di backend lama (default config).
const int _staleAfterHours = 72;

/// Mirror skema AnalyzeRequest (schemas.py).
class AnalyzeRequestData {
  const AnalyzeRequestData({
    required this.mode,
    this.query = '',
    this.price = 0,
    this.componentType,
    this.brand,
    this.model,
    this.cpu,
    this.gpu,
    this.ramGb,
    this.storageGb,
    this.screenSize,
    this.condition = 'any',
  });

  final String mode; // 'pc' | 'laptop'
  final String query;
  final int price;
  final String? componentType;
  final String? brand;
  final String? model;
  final String? cpu;
  final String? gpu;
  final int? ramGb;
  final int? storageGb;
  final double? screenSize;
  final String? condition;
}

/// Mirror skema Comparison (schemas.py).
class ComparisonData {
  const ComparisonData({
    required this.title,
    required this.price,
    required this.source,
    this.listingUrl,
    required this.similarity,
    this.condition,
  });

  final String title;
  final int price;
  final String source;
  final String? listingUrl;
  final double similarity;
  final String? condition;
}

/// Mirror skema Alternative (schemas.py) + field ekstra konsensus.
class AlternativeData {
  const AlternativeData({
    required this.name,
    required this.score,
    required this.estPriceIdr,
    required this.gainPercent,
    this.vramGb,
    this.tierLabel,
    this.nSources,
    this.scoreSource,
  });

  final String name;
  final int score;
  final int estPriceIdr;
  final int gainPercent;
  final int? vramGb;
  final String? tierLabel;
  final int? nSources;
  final String? scoreSource;
}

/// Mirror skema Freshness (schemas.py).
class FreshnessData {
  const FreshnessData({
    this.lastUpdatedAt,
    this.ageSeconds,
    required this.label,
    required this.isStale,
    required this.primarySource,
  });

  final DateTime? lastUpdatedAt;
  final int? ageSeconds;
  final String label;
  final bool isStale;
  final String primarySource;
}

/// Hasil analyze(): (ScoreResult, comparisons, freshness, alternatives).
class AnalysisOutcome {
  const AnalysisOutcome({
    required this.result,
    required this.comparisons,
    required this.freshness,
    required this.alternatives,
  });

  final ScoreResult result;
  final List<ComparisonData> comparisons;
  final FreshnessData freshness;
  final List<AlternativeData> alternatives;
}

/// Mirror skema BundleItemBreakdown (schemas.py).
class BundleItemData {
  const BundleItemData({
    required this.query,
    required this.componentType,
    this.priceInput,
    required this.referencePrice,
    this.newReferencePrice,
    this.usedReferencePrice,
  });

  final String query;
  final String componentType;
  final int? priceInput;
  final int referencePrice;
  final int? newReferencePrice;
  final int? usedReferencePrice;
}

/// Mirror skema BundleResponse (schemas.py).
class BundleOutcome {
  const BundleOutcome({
    required this.bundlePrice,
    required this.referenceTotal,
    this.newReferenceTotal,
    this.usedReferenceTotal,
    required this.score,
    required this.verdict,
    required this.recommendation,
    required this.savingsPercent,
    this.savingsUsedPercent,
    this.crossMarketAdvice,
    required this.items,
  });

  final int bundlePrice;
  final int referenceTotal;
  final int? newReferenceTotal;
  final int? usedReferenceTotal;
  final double score;
  final String verdict;
  final String recommendation;
  final double savingsPercent;
  final double? savingsUsedPercent;
  final String? crossMarketAdvice;
  final List<BundleItemData> items;
}

/// Padanan HTTPException 422 di endpoint analyze-bundle Python.
class BundleReferenceException implements Exception {
  const BundleReferenceException(this.detail);
  final String detail;
  @override
  String toString() => 'BundleReferenceException: $detail';
}

// ---------------------------------------------------------------------------
// Helper murni (port fungsi privat analysis.py)
// ---------------------------------------------------------------------------

double _agePenalty(DateTime? scrapedAt, DateTime now) {
  if (scrapedAt == null) return 0.0;
  final ts = scrapedAt.isUtc ? scrapedAt : scrapedAt.toUtc();
  var days = now.difference(ts).inMicroseconds / 1e6 / 86400.0;
  if (days < 0) days = 0.0;
  if (days <= 30) {
    return 0.0;
  } else if (days <= 60) {
    return 0.04;
  } else {
    return math.min(0.12, 0.04 + 0.04 * ((days - 60) / 30));
  }
}

Set<String> _tokens(String? value) {
  // Pisahkan huruf dan angka: 'rx6600' dan 'rx 6600' sama-sama
  // menghasilkan {'rx','6600'}.
  return RegExp(r'[a-z]+|\d+')
      .allMatches((value ?? '').toLowerCase())
      .map((m) => m.group(0)!)
      .where((t) => t.length > 1)
      .toSet();
}

const Set<String> _categoryWords = {
  'gpu', 'vga', 'card',
  'cpu', 'processor', 'prosesor',
  'ram', 'memori', 'memory',
  'ssd', 'hdd', 'nvme', 'storage', 'harddisk', 'hardisk',
  'motherboard', 'mobo', 'mainboard',
};

double _similarity(String query, String title) {
  final wanted = _tokens(query);
  final actual = _tokens(title);
  if (wanted.isEmpty || actual.isEmpty) return 0.0;
  wanted.removeAll(_categoryWords);
  if (wanted.isEmpty) return 0.0;
  // Token model yang ada di query tapi TIDAK di judul = penalti keras.
  final missing = wanted.difference(actual);
  if (missing.isNotEmpty) {
    return missing.length < wanted.length / 2
        ? pyRound(1.0 - 0.5 * missing.length / wanted.length, 3)
        : 0.0;
  }
  return pyRound(wanted.intersection(actual).length / wanted.length, 3);
}

/// Token identitas produk (chipset+suffix+kapasitas).
Set<String> _modelTokens(String? value, String? componentType) {
  final text = (value ?? '').toLowerCase();
  var m = RegExp(r'\b(rtx|gtx|rx|arc)\s*([ab]?\d{3,4})\s*(ti|super|xt)?\b')
      .firstMatch(text);
  if (m != null) {
    return {m.group(1)!, m.group(2)!, if (m.group(3) != null) m.group(3)!};
  }
  m = RegExp(r'\b(ryzen\s*[3579]|core\s*i[3579])\s*-?\s*(\d{4,5})([a-z]{0,2})?\b')
      .firstMatch(text);
  if (m != null) {
    final fam = m.group(1)!.contains('ryzen') ? 'ryzen' : 'core';
    return {
      fam,
      m.group(2)!,
      if (m.group(3) != null && m.group(3)!.isNotEmpty) m.group(3)!,
    };
  }
  final ddr = RegExp(r'ddr\s*([345])').firstMatch(text);
  final gb = RegExp(r'(\d{1,2})\s*gb\b').firstMatch(text);
  if (ddr != null && gb != null && componentType == 'ram') {
    return {'ddr${ddr.group(1)}', gb.group(1)!};
  }
  final tb = RegExp(r'(\d)\s*tb\b').firstMatch(text);
  if (componentType == 'storage') {
    final String? kind = RegExp(r'\bnvme\b|\bm\.?2\b').hasMatch(text)
        ? 'nvme'
        : (RegExp(r'\bssd\b').hasMatch(text) ? 'ssd' : null);
    final size = gb?.group(1) ?? tb?.group(1);
    if (kind != null && size != null) return {kind, size};
  }
  if (componentType == 'motherboard') {
    // Identitas mobo = chipset persis.
    final chipset = RegExp(r'\b([abxzi]\d{3})[a-z]{0,2}\b').firstMatch(text);
    return chipset != null ? {chipset.group(1)!} : <String>{};
  }
  return <String>{};
}

bool _isGbToken(String t) => RegExp(r'^\d{1,2}gb$').hasMatch(t);

/// Resolusi tipe komponen semantik Python `explicit or from_query`:
/// string kosong juga dianggap tidak diisi.
String? _resolveCtype(String? explicit, String query) =>
    (explicit == null || explicit.isEmpty)
        ? componentTypeFromQuery(query)
        : explicit;


/// Periksa kesesuaian token model (aturan kapasitas persis bila disebut).
bool _matchesModelTokens(Set<String> rowTokens, Set<String> requiredTokens) {
  if (requiredTokens.isEmpty) return true;
  final reqVram = requiredTokens.where(_isGbToken).toSet();
  if (reqVram.isNotEmpty) {
    return rowTokens.length == requiredTokens.length &&
        rowTokens.containsAll(requiredTokens);
  }
  final rowCore = rowTokens.where((t) => !_isGbToken(t)).toSet();
  return rowCore.length == requiredTokens.length &&
      rowCore.containsAll(requiredTokens);
}

/// Key model GPU/CPU dari query utk anchor harga baru.
String? _anchorKey(String? query) {
  final q = (query ?? '')
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .join(' ');
  var m = RegExp(r'\b(rtx|gtx)\s*(\d{3,4})\s*(ti|super)?\b').firstMatch(q);
  if (m != null) {
    return '${m.group(1)} ${m.group(2)}${m.group(3) != null ? ' ${m.group(3)}' : ''}';
  }
  m = RegExp(r'\brx\s*(\d{3,4})\s*(xt)?\b').firstMatch(q);
  if (m != null) {
    return 'rx ${m.group(1)}${m.group(2) != null ? ' xt' : ''}';
  }
  m = RegExp(r'\bryzen\s*([3579])\s*((?:9\d{3}|[357]\d{3}|\d{4}))\b').firstMatch(q);
  if (m != null) return 'ryzen ${m.group(1)} ${m.group(2)}';
  m = RegExp(r'\bcore\s*i([3579])\s*-?\s*((?:10|11|12|13|14)\d{3}|\d{4})\b')
      .firstMatch(q);
  if (m != null) return 'core i${m.group(1)} ${m.group(2)}';
  return null;
}

/// Bentuk kanonik dari query bebas: 'ram ddr4 16gb' -> 'RAM DDR4 16GB'.
String? _canonicalKey(String? value, String ctype) {
  final text = (value ?? '').toLowerCase();
  if (ctype == 'ram') {
    final ddr = RegExp(r'ddr\s*([345])').firstMatch(text);
    final gb = RegExp(r'(\d{1,2})\s*gb\b').firstMatch(text);
    if (ddr != null && gb != null) {
      return 'RAM DDR${ddr.group(1)} ${gb.group(1)}GB';
    }
    return null;
  }
  var kind = RegExp(r'\b(ssd|nvme|m\.?2)\b').hasMatch(text)
      ? 'SSD'
      : (RegExp(r'\bhdd\b|\bharddisk\b|\bhardisk\b').hasMatch(text)
          ? 'HDD'
          : null);
  if (kind == null) return null;
  if (kind == 'SSD') {
    kind = RegExp(r'nvme').hasMatch(text)
        ? 'SSD NVMe'
        : (RegExp(r'sata').hasMatch(text) ? 'SSD SATA' : 'SSD');
  }
  final gb = RegExp(r'(\d{1,3})\s*gb\b').firstMatch(text);
  final tb = RegExp(r'(\d)\s*tb\b').firstMatch(text);
  final size =
      gb != null ? '${gb.group(1)}GB' : (tb != null ? '${tb.group(1)}TB' : null);
  return size != null ? '$kind $size' : null;
}

String _ageLabel(int? seconds) {
  if (seconds == null) return 'belum ada data';
  if (seconds < 60) return 'baru saja';
  if (seconds < 3600) return '${seconds ~/ 60} menit lalu';
  if (seconds < 86400) return '${seconds ~/ 3600} jam lalu';
  return '${seconds ~/ 86400} hari lalu';
}

final RegExp _mdJunkRe = RegExp(
  r'\[!\[[^\]]*\]\([^)]*\)]?\([^)]*\)|!\[[^\]]*\]\([^)]*\)|\[Image\s*[^\]]*\]',
  caseSensitive: false,
);

/// Buang sampah markdown/gambar dan prefix query dari judul hasil scrape.
String _cleanTitle(String? text) {
  var raw = text ?? '';
  final subbed =
      raw.replaceFirst(RegExp(r'^[^\u2014\ufffc]+[\u2014\ufffc]\s*'), '').trim();
  if (subbed.isNotEmpty) raw = subbed;
  final cleaned = raw.replaceAll(_mdJunkRe, ' ');
  final joined =
      cleaned.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).join(' ');
  return joined.length > 180 ? joined.substring(0, 180) : joined;
}

/// Hanya sediakan link eksternal dari marketplace online riil.
bool _isExternalLinkAllowed(String? source, String? url) {
  if (url == null || url.isEmpty) return false;
  final src = (source ?? '').toLowerCase();
  if (<String>{
    'komponen_retail', 'notebook_retail', 'price_reference', 'data',
    'benchmark', 'enterkomputer',
  }.contains(src)) {
    return false;
  }
  if (url.toLowerCase().contains('enterkomputer')) return false;
  return true;
}

/// Format ribuan ala f"{n:,}".replace(",", ".") Python: 4500000 -> "4.500.000".
String _grouped(int n) {
  final neg = n < 0;
  final digits = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  return (neg ? '-' : '') + buf.toString();
}

/// Median atas ala Python sorted(prices)[len//2].
int _upperMedian(List<int> prices) {
  final sorted = List<int>.of(prices)..sort();
  return sorted[sorted.length ~/ 2];
}

// ---------------------------------------------------------------------------
// Mesin analisis
// ---------------------------------------------------------------------------

class _Scored {
  _Scored(this.sim, this.row, this.cleanTitle);
  final double sim;
  final ListingRow row;
  final String cleanTitle;
}

class AnalysisEngine {
  AnalysisEngine(this.data, this.listings) : benchmark = Benchmark(data);

  final BenchmarkData data;
  final ListingsSource listings;
  final Benchmark benchmark;

  /// Harga retail mobo dari katalog: match nama paling mirip (subset token).
  int? _moboAnchor(String query) {
    final cat = data.retail['motherboard'];
    if (cat is! List) return null;
    final qtok = RegExp(r'[a-z0-9]+')
        .allMatches(query.toLowerCase())
        .map((m) => m.group(0)!)
        .where((t) => t.length > 1)
        .toSet();
    (double, int)? best;
    for (final prod in cat) {
      if (prod is! Map) continue;
      final price = prod['price'];
      final model = (prod['model'] as String? ?? '').toLowerCase();
      if (price is! int || model.isEmpty) continue;
      final ptok = RegExp(r'[a-z0-9]+')
          .allMatches(model)
          .map((m) => m.group(0)!)
          .where((t) => t.length > 1)
          .toSet();
      if (qtok.isNotEmpty &&
          ptok.isNotEmpty &&
          qtok.every(ptok.contains)) {
        final overlap = qtok.intersection(ptok).length / qtok.length;
        if (best == null || overlap > best.$1) best = (overlap, price);
      }
    }
    return best?.$2;
  }

  /// Port new_price_anchor(): harga BARU referensi (IDR) untuk query
  /// GPU/CPU/RAM/storage/motherboard; null kalau gak ketemu.
  int? newPriceAnchor(String query, [String? componentType]) {
    final ctype = _resolveCtype(componentType, query);
    if (ctype == 'ram' || ctype == 'storage') {
      final canon = data.retail['${ctype}_canonical'];
      final key = _canonicalKey(query, ctype!);
      final price = (canon is Map && key != null) ? canon[key] : null;
      return (price is num && price != 0) ? price.toInt() : null;
    }

    final ref = data.newPriceRef;
    if (ctype == 'motherboard') return _moboAnchor(query);
    final key = _anchorKey(query);
    if (key == null) return null;

    // ponytail: exact-match saja utk harga retail — "rtx 3060 ti" produk BEDA.
    final retailIdr = ref['retail_idr'];
    for (final bucket in ['gpu', 'cpu']) {
      final bucketMap = retailIdr is Map ? retailIdr[bucket] : null;
      final price = bucketMap is Map ? bucketMap[key] : null;
      if (price is num && price != 0) return price.toInt();
    }

    num? usd;
    final gpuMap = ref['gpu'];
    final cpuMap = ref['cpu'];
    if (gpuMap is Map && gpuMap[key] is num) usd = gpuMap[key] as num;
    if (usd == null || usd == 0) {
      usd = (cpuMap is Map && cpuMap[key] is num) ? cpuMap[key] as num : null;
    }
    if (usd == null || usd == 0) return null;
    return (usd * usdToIdr * retailMarkup).toInt();
  }

  Future<List<ComparisonData>> _pcComparisons(AnalyzeRequestData request) async {
    final ctype = _resolveCtype(request.componentType, request.query);

    const retailCatsMap = <String, List<String>>{
      'gpu': ['vga'],
      'cpu': ['processor'],
      'motherboard': ['motherboard'],
      'ram': ['ram'],
      'storage': ['ssd', 'harddisk'],
    };
    final retailCats = retailCatsMap[ctype] ??
        const ['vga', 'processor', 'motherboard', 'ram', 'ssd', 'harddisk'];

    // Token angka/model utama dari query user (misal '4060', '12400')
    final mNum = RegExp(r'\b(\d{3,5})\b').firstMatch(request.query);
    final modelNum = mNum?.group(1);

    final allCats = ctype != null
        ? ['pc', ...retailCats]
        : const ['pc', 'vga', 'processor', 'motherboard', 'ram', 'ssd', 'harddisk'];

    var rows = await listings.pcListings(modelNum: modelNum, categories: allCats);

    // Fallback Python per-sumber digabung satu panggilan seam (lihat
    // catatan seam di header file); dedupe kunci komposit ganti id.
    if (rows.length < 10 && modelNum == null) {
      final extra =
          await listings.pcListings(categories: ['pc', ...retailCats]);
      final seen = <String>{};
      String keyOf(ListingRow r) =>
          '${r.source}|${r.title}|${r.price}|${r.url}';
      rows = [
        for (final r in [...rows, ...extra])
          if (seen.add(keyOf(r))) r,
      ];
    }

    final now = DateTime.now().toUtc();
    final required = _modelTokens(request.query, ctype);

    final scoredExact = <_Scored>[];
    final scoredFamily = <_Scored>[];
    for (final row in rows) {
      final cleanT = _cleanTitle(row.title);
      if (!isRelevantPcListing(request.query, cleanT, ctype)) continue;
      final sim = math.max(
        0.05,
        _similarity(request.query, cleanT) - _agePenalty(row.scrapedAt, now),
      );
      final rowToks = _modelTokens(cleanT, ctype);
      if (_matchesModelTokens(rowToks, required)) {
        scoredExact.add(_Scored(sim, row, cleanT));
      } else if (required.isNotEmpty &&
          _setEq(
            rowToks.where((t) => !_isGbToken(t)).toSet(),
            required.where((t) => !_isGbToken(t)).toSet(),
          )) {
        // Model sekeluarga tapi kapasitas VRAM beda.
        scoredFamily.add(_Scored(math.max(0.05, sim * 0.88), row, cleanT));
      }
    }

    final matchingExact = scoredExact.where((i) => i.sim >= 0.75).toList();
    final matchingFamily = scoredFamily.where((i) => i.sim >= 0.65).toList();

    // Pisahkan per kondisi
    final wantedCond = request.condition;
    List<_Scored> exactCond, familyCond, otherCond;
    if (wantedCond != null && wantedCond.isNotEmpty && wantedCond != 'any') {
      exactCond = matchingExact
          .where((i) => (i.row.condition ?? 'new') == wantedCond)
          .toList();
      familyCond = matchingFamily
          .where((i) => (i.row.condition ?? 'new') == wantedCond)
          .toList();
      otherCond = matchingExact
          .where((i) => (i.row.condition ?? 'new') != wantedCond)
          .toList();
    } else {
      exactCond = matchingExact;
      familyCond = matchingFamily;
      otherCond = [];
    }

    List<_Scored> dedupItems(List<_Scored> items) {
      final seen = <(String?, String, int)>{};
      final deduped = <_Scored>[];
      for (final item in items) {
        final t = item.cleanTitle;
        final key = (
          item.row.source,
          (t.length > 60 ? t.substring(0, 60) : t).toLowerCase(),
          item.row.price,
        );
        if (seen.add(key)) deduped.add(item);
      }
      return deduped;
    }

    exactCond = dedupItems(exactCond);
    familyCond = dedupItems(familyCond);
    otherCond = dedupItems(otherCond);

    List<_Scored> filterOutliers(List<_Scored> items) {
      if (items.length < 4) return items;
      final prices = items.map((it) => it.row.price).toList()..sort();
      final q1 = prices[prices.length ~/ 4];
      final q3 = prices[(3 * prices.length) ~/ 4];
      final iqr = q3 - q1;
      final lo = q1 - 1.5 * iqr;
      final hi = q3 + 1.5 * iqr;
      final inliers =
          items.where((it) => it.row.price >= lo && it.row.price <= hi).toList();
      return inliers.isNotEmpty ? inliers : items;
    }

    final cleanExact = filterOutliers(exactCond);
    final cleanFamily = filterOutliers(familyCond);

    // Kumpulkan pembanding: utamakan exact match.
    final pool = List<_Scored>.of(cleanExact);

    // JAMIN MINIMAL 10 PEMBANDING REAL dari family se-kondisi.
    if (pool.length < 10 && cleanFamily.isNotEmpty) {
      pool.addAll(cleanFamily.take(10 - pool.length));
    }

    // Isi dari kondisi lain hanya bila user tidak memilih kondisi spesifik.
    if ((wantedCond == null || wantedCond.isEmpty || wantedCond == 'any') &&
        pool.length < 10 &&
        otherCond.isNotEmpty) {
      pool.addAll(otherCond.take(10 - pool.length));
    }

    final retailComparisons =
        _retailComparisons(request.query, ctype, request.condition);
    if (pool.isEmpty) return retailComparisons;

    // Urutkan: kemiripan tertinggi, lalu kedekatan dengan median.
    final prices = pool.map((i) => i.row.price).toList()..sort();
    final anchor = prices[prices.length ~/ 2];
    stableSort(pool, (a, b) {
      final bySim = b.sim.compareTo(a.sim);
      if (bySim != 0) return bySim;
      final da = (a.row.price - anchor).abs();
      final db = (b.row.price - anchor).abs();
      return da.compareTo(db);
    });

    // Distribusi sumber seimbang tanpa memotong pool di bawah 10.
    final bySource = <String, List<_Scored>>{};
    for (final item in pool) {
      bySource.putIfAbsent(item.row.source ?? 'lain', () => []).add(item);
    }

    final selected = <_Scored>[];
    final maxTarget = math.max(10, math.min(24, pool.length));
    var quota = (maxTarget + bySource.length - 1) ~/ bySource.length;
    if (quota < 3) quota = 3;
    final sourcePools = [
      for (final p in bySource.values) p.take(quota).toList(),
    ];
    while (sourcePools.any((p) => p.isNotEmpty) &&
        selected.length < maxTarget) {
      for (final p in sourcePools) {
        if (p.isNotEmpty && selected.length < maxTarget) {
          selected.add(p.removeAt(0));
        }
      }
    }

    if (selected.length < 10 && pool.length >= 10) {
      final seenItems = selected.toSet();
      for (final it in pool) {
        if (!seenItems.contains(it)) {
          selected.add(it);
          seenItems.add(it);
          if (selected.length >= 10) break;
        }
      }
    }

    return [
      for (final item in selected)
        ComparisonData(
          title: _cleanTitle(item.row.title),
          price: item.row.price,
          source: item.row.source ?? '',
          listingUrl: _isExternalLinkAllowed(item.row.source, item.row.url)
              ? item.row.url
              : null,
          similarity: item.sim,
          condition: item.row.condition ?? 'new',
        ),
      ...retailComparisons,
    ];
  }

  bool _setEq(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  /// Pembanding dari katalog retail bundel (produk baru).
  List<ComparisonData> _retailComparisons(
    String query,
    String? componentType,
    String? condition,
  ) {
    if (condition == 'second' || condition == 'bekas' || componentType == 'laptop') {
      return [];
    }
    final catalog = data.retail;
    const sectionsMap = <String, List<String>>{
      'gpu': ['gpu'],
      'cpu': ['cpu'],
      'motherboard': ['motherboard'],
      'ram': ['ram'],
      'storage': ['storage'],
    };
    final sections = sectionsMap[componentType] ??
        const ['gpu', 'cpu', 'motherboard', 'ram', 'storage'];

    final required = _modelTokens(query, componentType);
    final candidates = <(double, int, String)>[];
    for (final section in sections) {
      final list = catalog[section];
      if (list is! List) continue;
      for (final product in list) {
        if (product is! Map) continue;
        final title = (product['model'] as String? ?? '').trim();
        final price = product['price'];
        if (title.isEmpty || price is! int || price < 50000) continue;
        if (!isRelevantPcListing(query, title, componentType)) continue;
        final similarity = _similarity(query, title);
        if (similarity < 0.75) continue;
        if (!_matchesModelTokens(
            _modelTokens(title, componentType), required)) {
          continue;
        }
        candidates.add((similarity, price, title));
      }
    }

    // Python: sort key (sim, -price) reverse=True -> sim desc, price asc.
    stableSort(candidates, (a, b) {
      final bySim = b.$1.compareTo(a.$1);
      if (bySim != 0) return bySim;
      return a.$2.compareTo(b.$2);
    });
    return [
      for (final c in candidates.take(12))
        ComparisonData(
          title: c.$3,
          price: c.$2,
          source: 'komponen_retail',
          listingUrl: null,
          similarity: c.$1,
          condition: 'new',
        ),
    ];
  }

  // -------------------------------------------------------------------------
  // Mode laptop
  // -------------------------------------------------------------------------

  Future<(List<ComparisonData>, Map<String, Map<String, String?>>)>
      _laptopComparisons(AnalyzeRequestData request) async {
    final gpuOrQuery = (request.gpu != null && request.gpu!.isNotEmpty)
        ? request.gpu!
        : request.query;
    final wantGpu = _gpuSig(gpuOrQuery);
    var wantCpu = _cpuSig(request.cpu);
    if (wantCpu == null && (request.gpu == null || request.gpu!.isEmpty)) {
      wantCpu = _cpuSig(request.query);
    }

    final gpuNumMatch = RegExp(r'\b(\d{3,4})\b').firstMatch(gpuOrQuery);
    final gpuNum = gpuNumMatch?.group(1);

    const genericWords = {
      'laptop', 'notebook', 'gaming', 'pro', 'plus', 'max', 'ultra',
      'inch', 'ti', 'super', 'intel', 'amd',
    };
    final queryTokens = _tokens('${request.brand ?? ''} ${request.query}')
        .where((t) => !genericWords.contains(t) && t.length >= 3)
        .toList();

    final seamTokens = <String>[
      if (gpuNum != null) gpuNum,
      ...queryTokens,
    ];
    var rows = _laptopRowsFromMaps(await listings.laptopUnits(tokens: seamTokens));

    if (rows.length < 30) {
      // Fallback Python per-sumber (notebook_retail/tokopedia) digabung
      // satu panggilan seam tanpa token; dedupe kunci komposit.
      final extra = _laptopRowsFromMaps(await listings.laptopUnits(tokens: const []));
      String keyOf(_LaptopRow r) =>
          '${r.brand}|${r.model}|${r.price}|${r.source}|${r.scrapedAt}';
      final seen = rows.map(keyOf).toSet();
      for (final r in extra) {
        if (seen.add(keyOf(r))) rows.add(r);
      }
    }

    // Python: request.ram_gb or None -> 0 dianggap tidak diisi.
    final minRam = (request.ramGb == null || request.ramGb == 0)
        ? null
        : request.ramGb;
    final minStorage = (request.storageGb == null || request.storageGb == 0)
        ? null
        : request.storageGb;
    final scoredNew = <(double, _LaptopRow)>[];
    final scoredUsed = <(double, _LaptopRow)>[];
    final now = DateTime.now().toUtc();
    final wanted = _tokens('${request.brand ?? ''} ${request.query}');
    final queryParts = request.query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    final brandPrefix = request.query.isNotEmpty
        ? (queryParts.isNotEmpty ? queryParts[0] : '')
        : (request.brand ?? '').toLowerCase();

    for (final row in rows) {
      final title =
          '${row.brand ?? ''} ${row.model ?? ''} ${row.cpu ?? ''} ${row.gpu ?? ''}';
      if (!isRelevantPcListing(request.query, title, 'laptop')) continue;
      final gotGpu = _gpuSig(title);
      final gotCpu = _cpuSig(title);

      // GPU = identitas performa utama laptop gaming.
      if (wantGpu != null && gotGpu != wantGpu) continue;

      var cpuPenalty = 0.0;
      if (wantCpu != null) {
        final gotTier = gotCpu != null ? _cpuTier(gotCpu) : null;
        final wantTier = _cpuTier(wantCpu);
        if (gotCpu == wantCpu) {
          // pas
        } else if (gotTier != null && gotTier == wantTier) {
          cpuPenalty = 0.10;
        } else if (gotTier != null &&
            wantTier != null &&
            gotTier.compareTo(wantTier) > 0) {
          cpuPenalty = 0.15;
        } else if (gotCpu == null) {
          cpuPenalty = 0.20;
        } else {
          continue; // kelas di bawah yang diminta
        }
      }

      // Python: row.ram_gb or extract(...) -> 0 juga fallback ke teks.
      final effectiveRam = (row.ramGb == null || row.ramGb == 0)
          ? _extractRamFromText(title)
          : row.ramGb;
      final effectiveStorage = (row.storageGb == null || row.storageGb == 0)
          ? _extractStorageFromText(title)
          : row.storageGb;
      var specPenalty = 0.0;
      if (minRam != null) {
        if (effectiveRam != null && effectiveRam < minRam) {
          if (effectiveRam <= minRam ~/ 2) continue;
          specPenalty += 0.10;
        } else if (effectiveRam == null) {
          specPenalty += 0.05;
        }
      }
      if (minStorage != null) {
        if (effectiveStorage != null && effectiveStorage < minStorage) {
          if (effectiveStorage <= minStorage ~/ 2) continue;
          specPenalty += 0.10;
        } else if (effectiveStorage == null) {
          specPenalty += 0.05;
        }
      }

      final actual = _tokens('${row.brand ?? ''} ${row.model ?? ''}');
      final double rawSim;
      if (wanted.isNotEmpty) {
        final overlap = wanted.intersection(actual).length;
        final overlapSim = pyRound(overlap / wanted.length, 3);
        // Baseline kemiripan: GPU sama persis -> minimal 0.50.
        final base =
            (wantGpu != null && gotGpu == wantGpu) ? 0.50 : 0.30;
        var sim = math.max(base, overlapSim);
        if (brandPrefix.isNotEmpty && actual.contains(brandPrefix)) {
          sim = math.min(1.0, sim + 0.15);
        }
        for (final qt in queryTokens) {
          if (actual.contains(qt)) {
            sim = math.min(1.0, sim + 0.20);
            break;
          }
        }
        rawSim = sim;
      } else {
        rawSim = 0.5;
      }

      final similarity = math.max(
        0.05,
        rawSim - cpuPenalty - specPenalty - _agePenalty(row.scrapedAt, now),
      );
      if (row.condition == 'second') {
        scoredUsed.add((similarity, row));
      } else {
        scoredNew.add((similarity, row));
      }
    }

    if (scoredNew.isEmpty && scoredUsed.isEmpty) {
      return (<ComparisonData>[], <String, Map<String, String?>>{});
    }

    List<(double, _LaptopRow)> processPool(
      List<(double, _LaptopRow)> candidates,
      int limitCount,
    ) {
      if (candidates.isEmpty) return [];
      // Python mengurutkan list kandidat IN-PLACE; disamakan di sini.
      final cands = candidates;
      stableSort(cands, (a, b) {
        final bySim = b.$1.compareTo(a.$1);
        if (bySim != 0) return bySim;
        final ta = a.$2.scrapedAt;
        final tb = b.$2.scrapedAt;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });
      final highSim = cands.where((i) => i.$1 >= 0.4).toList();
      var pool = highSim.length >= 3 ? highSim : cands;
      var topCandidates = pool.take(50).toList();
      final prices = topCandidates
          .map((i) => i.$2.price)
          .where((p) => p != 0)
          .toList()
        ..sort();
      if (prices.length >= 4) {
        final q1 = prices[prices.length ~/ 4];
        final q3 = prices[(3 * prices.length) ~/ 4];
        final iqr = q3 - q1;
        final lo = math.max(500000, q1 - 1.5 * iqr);
        final hi = q3 + 1.5 * iqr;
        final inliers = topCandidates
            .where((i) => i.$2.price >= lo && i.$2.price <= hi)
            .toList();
        topCandidates = inliers.isNotEmpty ? inliers : topCandidates;
      }

      final bySource = <String, List<(double, _LaptopRow)>>{};
      final seenTitles = <String>{};
      String titleKey(_LaptopRow r) {
        final t = _cleanTitle(r.model ?? r.brand ?? 'Laptop').toLowerCase();
        return t.length > 80 ? t.substring(0, 80) : t;
      }

      for (final item in topCandidates) {
        final tk = titleKey(item.$2);
        if (seenTitles.contains(tk)) continue;
        seenTitles.add(tk);
        bySource.putIfAbsent(item.$2.source ?? 'lain', () => []).add(item);
      }

      int totalItems() =>
          bySource.values.fold(0, (s, v) => s + v.length);
      if (totalItems() < limitCount) {
        for (final item in cands) {
          final tk = titleKey(item.$2);
          if (!seenTitles.contains(tk)) {
            seenTitles.add(tk);
            bySource
                .putIfAbsent(item.$2.source ?? 'lain', () => [])
                .add(item);
            if (totalItems() >= limitCount) break;
          }
        }
      }

      var quota = (limitCount + bySource.length - 1) ~/ bySource.length;
      if (quota < 2) quota = 2;
      final pools = [
        for (final p in bySource.values) p.take(quota).toList(),
      ];
      final selectedItems = <(double, _LaptopRow)>[];
      while (pools.any((p) => p.isNotEmpty) &&
          selectedItems.length < limitCount) {
        for (final p in pools) {
          if (p.isNotEmpty && selectedItems.length < limitCount) {
            selectedItems.add(p.removeAt(0));
          }
        }
      }
      return selectedItems;
    }

    final List<(double, _LaptopRow)> selected;
    if (request.condition == 'new') {
      final selNew = processPool(scoredNew, 16);
      final selUsed = processPool(scoredUsed, 8);
      selected = selNew.isNotEmpty
          ? [...selNew, ...selUsed]
          : processPool([...scoredUsed, ...scoredNew], 24);
    } else if (request.condition == 'second') {
      final selUsed = processPool(scoredUsed, 16);
      final selNew = processPool(scoredNew, 8);
      selected = selUsed.isNotEmpty
          ? [...selUsed, ...selNew]
          : processPool([...scoredNew, ...scoredUsed], 24);
    } else {
      final selNew = processPool(scoredNew, 12);
      final selUsed = processPool(scoredUsed, 12);
      selected = (selNew.isNotEmpty || selUsed.isNotEmpty)
          ? [...selNew, ...selUsed]
          : processPool([...scoredNew, ...scoredUsed], 24);
    }

    return (
      [
        for (final (similarity, row) in selected)
          ComparisonData(
            title: _cleanTitle(row.model ?? row.brand ?? 'Laptop'),
            price: row.price,
            source: row.source ?? '',
            listingUrl: _isExternalLinkAllowed(row.source, row.listingUrl)
                ? row.listingUrl
                : null,
            similarity: similarity,
            condition: row.condition ?? 'new',
          ),
      ],
      {
        for (final (_, row) in selected)
          _cleanTitle(row.model ?? row.brand ?? 'Laptop'): {
            'cpu': row.cpu,
            'gpu': row.gpu,
          },
      },
    );
  }

  // -------------------------------------------------------------------------
  // Advice benchmark
  // -------------------------------------------------------------------------

  (String, List<AlternativeData>) _benchmarkAdvice(
    AnalyzeRequestData request,
    ScoreResult result,
  ) {
    final ctype =
        _resolveCtype(request.componentType, request.query);
    // PassMark = guard performa utama; konsensus hanya untuk model
    // tanpa skor PassMark (perilaku backend saat ini).
    final basePassmark = benchmark.passmarkScore(request.query, ctype);
    final List<Map<String, Object?>> alts;
    final bool useConsensus;
    if (basePassmark != null) {
      alts = benchmark.betterAlternatives(
          request.query, ctype, request.price, usdToIdr.toDouble());
      useConsensus = false;
    } else {
      alts = benchmark.betterAlternativesConsensus(
          request.query, ctype, request.price, usdToIdr.toDouble());
      useConsensus = alts.isNotEmpty;
    }
    if (alts.isEmpty) return ('', const []);
    final best = alts[0];
    final estPriceStr = _grouped((best['est_price_idr'] as num).toInt());
    final budgetPriceStr = _grouped(request.price);
    final String srcStr;
    if (useConsensus) {
      srcStr =
          "skor konsensus ${best['score']}/100 (${best['n_sources'] ?? '?'} sumber)";
    } else {
      srcStr = "skor PassMark ${_grouped((best['score'] as num).toInt())}";
    }
    final gainStr = "+${best['gain_percent']}%";
    final String advice;
    if (result.verdict == 'worth it' || result.verdict == 'wajar') {
      advice = 'Dengan budget input Rp$budgetPriceStr, ada alternatif dengan '
          'performa lebih tinggi yang masih masuk budget: ${best['name']} '
          '(performa $gainStr, estimasi Rp$estPriceStr, $srcStr).';
    } else {
      advice = 'Dengan budget input Rp$budgetPriceStr, alternatif performa '
          'lebih tinggi yang masih masuk budget adalah ${best['name']} '
          '(performa $gainStr, estimasi Rp$estPriceStr, $srcStr).';
    }
    return (advice, [for (final a in alts) _alternativeFromMap(a)]);
  }

  (String, List<AlternativeData>) _laptopBenchmarkAdvice(
    AnalyzeRequestData request,
    List<ComparisonData> comparisons,
    Map<String, Map<String, String?>> specMap,
    ScoreResult result,
  ) {
    final userCombo = benchmark.laptopComboScore(
      (request.cpu != null && request.cpu!.isNotEmpty)
          ? request.cpu
          : request.query,
      (request.gpu != null && request.gpu!.isNotEmpty)
          ? request.gpu
          : request.query,
    );
    if (userCombo == null) return ('', const []);
    final userScore = (userCombo['score'] as num).toInt();
    final candidates = <(String, int, Map<String, Object?>)>[];
    for (final c in comparisons) {
      final spec = specMap[c.title] ?? const <String, String?>{};
      final combo = benchmark.laptopComboScore(spec['cpu'], spec['gpu']);
      if (combo != null && c.price <= request.price) {
        candidates.add((c.title, c.price, combo));
      }
    }
    final minScore = userScore * 1.15;
    final better = candidates
        .where((x) => (x.$3['score'] as num) >= minScore)
        .toList();
    stableSort(
        better, (a, b) => (b.$3['score'] as num).compareTo(a.$3['score'] as num));
    final alts = <AlternativeData>[
      for (final x in better.take(2))
        AlternativeData(
          name: x.$1,
          score: (x.$3['score'] as num).toInt(),
          estPriceIdr: x.$2,
          gainPercent:
              pyRoundInt(((x.$3['score'] as num) / userScore - 1) * 100),
        ),
    ];
    if (alts.isEmpty) return ('', const []);
    final best = alts[0];
    final estPriceStr = _grouped(best.estPriceIdr);
    final scoreStr = _grouped(best.score);
    final userScoreStr = _grouped(userScore);
    final String advice;
    if (result.verdict == 'worth it' || result.verdict == 'wajar') {
      advice = 'Ada alternatif unit dengan performa lebih tinggi di kisaran '
          'harga serupa: ${best.name} (performa +${best.gainPercent}%, dijual '
          'Rp$estPriceStr, skor combo $scoreStr vs $userScoreStr).';
    } else {
      advice = 'Di harga segitu lebih baik ${best.name}: performa '
          '+${best.gainPercent}% (dijual Rp$estPriceStr, skor combo '
          '$scoreStr vs $userScoreStr).';
    }
    return (advice, alts);
  }

  AlternativeData _alternativeFromMap(Map<String, Object?> m) => AlternativeData(
        name: m['name'] as String? ?? '',
        score: (m['score'] as num?)?.toInt() ?? 0,
        estPriceIdr: (m['est_price_idr'] as num?)?.toInt() ?? 0,
        gainPercent: (m['gain_percent'] as num?)?.toInt() ?? 0,
        vramGb: (m['vram_gb'] as num?)?.toInt(),
        tierLabel: m['tier_label'] as String?,
        nSources: (m['n_sources'] as num?)?.toInt(),
        scoreSource: m['score_source'] as String?,
      );

  // -------------------------------------------------------------------------
  // Freshness (aproksimasi seam — lihat catatan header)
  // -------------------------------------------------------------------------

  Future<FreshnessData> _freshness(String selectedSource) async {
    final ts = await listings.latestScrapedAt();
    if (ts == null) {
      return FreshnessData(
        label: _ageLabel(null),
        isStale: true,
        primarySource: selectedSource,
      );
    }
    final utc = ts.toUtc();
    var age = DateTime.now().toUtc().difference(utc).inSeconds;
    if (age < 0) age = 0;
    return FreshnessData(
      lastUpdatedAt: utc,
      ageSeconds: age,
      label: _ageLabel(age),
      isStale: age > _staleAfterHours * 3600,
      primarySource: selectedSource,
    );
  }

  // -------------------------------------------------------------------------
  // analyze / search
  // -------------------------------------------------------------------------

  /// Port analyze() Python.
  Future<AnalysisOutcome> analyze(AnalyzeRequestData request) async {
    String? tierLabel;
    final List<ComparisonData> comparisons;
    var specMap = <String, Map<String, String?>>{};
    if (request.mode == 'pc') {
      comparisons = await _pcComparisons(request);
      final ctype =
          _resolveCtype(request.componentType, request.query);
      // Tier dari skor konsensus multi-sumber bila ada; fallback PassMark.
      final con = benchmark.consensusLookup(request.query, ctype);
      final conScore = con == null ? null : (con['consensus_score'] as num?);
      if (con != null && conScore != null) {
        tierLabel = '${benchmark.consensusTierLabel(conScore)} '
            '(skor konsensus ${pyRoundInt(conScore.toDouble())}/100, '
            '${con['n_sources']} sumber)';
      } else {
        final base = benchmark.passmarkScore(request.query, ctype);
        final baseScore = base == null ? null : (base['score'] as num?);
        if (baseScore != null && baseScore != 0) {
          tierLabel = benchmark.getTierLabel(baseScore, ctype);
        }
      }
    } else {
      final (comps, specs) = await _laptopComparisons(request);
      comparisons = comps;
      specMap = specs;
      final userCombo = benchmark.laptopComboScore(
        (request.cpu != null && request.cpu!.isNotEmpty)
            ? request.cpu
            : request.query,
        (request.gpu != null && request.gpu!.isNotEmpty)
            ? request.gpu
            : request.query,
      );
      if (userCombo != null) {
        tierLabel = userCombo['tier_label'] as String?;
      }
    }

    // Dual-market reference calculation
    final newComps =
        comparisons.where((c) => (c.condition ?? 'new') == 'new').toList();
    final usedComps =
        comparisons.where((c) => c.condition == 'second').toList();
    final newPrices = newComps.map((c) => c.price).where((p) => p != 0).toList();
    final usedPrices =
        usedComps.map((c) => c.price).where((p) => p != 0).toList();

    int? newRef = newPrices.isNotEmpty ? _upperMedian(newPrices) : null;
    int? usedRef = usedPrices.isNotEmpty ? _upperMedian(usedPrices) : null;

    // Harga pembanding primer berdasarkan preferensi kondisi user
    final List<int> primaryPrices;
    if (request.condition == 'new' && newPrices.length >= 2) {
      primaryPrices = newPrices;
    } else if (request.condition == 'second' && usedPrices.length >= 2) {
      primaryPrices = usedPrices;
    } else {
      primaryPrices =
          comparisons.map((c) => c.price).where((p) => p != 0).toList();
    }

    var result = scorePrice(request.price, primaryPrices);
    var compsFinal = comparisons;

    // Fallback anchor harga BARU bila listing tak cukup untuk verdict.
    if ((result.verdict == 'data terbatas' || compsFinal.isEmpty) &&
        request.condition != 'second') {
      final refNew = newPriceAnchor(request.query, request.componentType);
      if (refNew != null) {
        result = scorePrice(request.price, [refNew], isNewReference: true);
        newRef ??= refNew;
        if (compsFinal.isEmpty) {
          compsFinal = [
            ComparisonData(
              title:
                  'Reference harga baru ${request.query} (katalog retail, bukan listing marketplace)',
              price: refNew,
              source: 'price_reference',
              listingUrl: null,
              similarity: 0.5,
              condition: 'new',
            ),
          ];
        }
      }
    }

    final crossAdvice = _generateCrossMarketAdvice(
      condition: request.condition,
      price: request.price,
      newRef: newRef,
      usedRef: usedRef,
    );

    // Sumber utama = sumber paling banyak di pembanding.
    final String selectedSource;
    if (compsFinal.isNotEmpty) {
      final counts = <String, int>{};
      for (final c in compsFinal) {
        counts[c.source] = (counts[c.source] ?? 0) + 1;
      }
      var bestSource = counts.keys.first;
      for (final e in counts.entries) {
        if (e.value > counts[bestSource]!) bestSource = e.key;
      }
      selectedSource = bestSource;
    } else {
      selectedSource = 'tokopedia';
    }

    // Sinyal benchmark: kalau harga jelek, kasih alternatif konkret.
    final (advice, alternatives) = request.mode == 'laptop'
        ? _laptopBenchmarkAdvice(request, compsFinal, specMap, result)
        : _benchmarkAdvice(request, result);

    var fullRec = result.recommendation;
    if (advice.isNotEmpty) fullRec = '$fullRec $advice';

    final finalResult = ScoreResult(
      score: result.score,
      verdict: result.verdict,
      recommendation: fullRec,
      referencePrice: result.referencePrice,
      deltaPercent: result.deltaPercent,
      fairPriceLow: result.fairPriceLow,
      fairPriceHigh: result.fairPriceHigh,
      tierLabel: tierLabel,
      newReferencePrice: newRef,
      usedReferencePrice: usedRef,
      crossMarketAdvice: crossAdvice,
    );

    return AnalysisOutcome(
      result: finalResult,
      comparisons: compsFinal,
      freshness: await _freshness(selectedSource),
      alternatives: alternatives,
    );
  }

  /// Port search_comparisons(): listing cocok tanpa skor/benchmark.
  Future<List<ComparisonData>> search(AnalyzeRequestData request) async {
    if (request.mode == 'pc') return _pcComparisons(request);
    final (comps, _) = await _laptopComparisons(request);
    return comps;
  }

  // -------------------------------------------------------------------------
  // Bundle (port resolve_bundle_item_prices + endpoint analyze-bundle)
  // -------------------------------------------------------------------------

  /// Resolusi harga baru & bekas 1 item bundle.
  /// Return record (reference_price, new_reference_price, used_reference_price).
  Future<(int, int?, int?)> resolveBundleItemPrices(
    String query,
    String? componentType,
  ) async {
    final ctype = _resolveCtype(componentType, query);

    // 1. Anchor harga baru retail.
    final anchor = newPriceAnchor(query, ctype);

    // 2. Pembanding database.
    final req = AnalyzeRequestData(
      mode: 'pc',
      query: query,
      price: 1,
      componentType: ctype,
      condition: 'any',
    );
    final comps = await _pcComparisons(req);
    final newPrices = comps
        .where((c) => (c.condition ?? 'new') == 'new' && c.price > 0)
        .map((c) => c.price)
        .toList();
    final usedPrices = comps
        .where((c) => c.condition == 'second' && c.price > 0)
        .map((c) => c.price)
        .toList();

    // 3. Fallback pencocokan langsung bila comps kosong dan anchor belum ada.
    if (newPrices.isEmpty && anchor == null) {
      final tokens = _modelTokens(query, ctype);
      if (tokens.isNotEmpty) {
        final directRows = await listings.pcListings(
          categories: const [
            'vga', 'processor', 'motherboard', 'ram', 'ssd', 'harddisk', 'pc',
          ],
        );
        var count = 0;
        for (final r in directRows) {
          if (count >= 3000) break;
          count++;
          if (r.price > 0) {
            final rt = r.title.toLowerCase();
            if (tokens.every((t) => rt.contains(t)) &&
                isRelevantPcListing(query, r.title, ctype)) {
              if (r.condition == 'second') {
                usedPrices.add(r.price);
              } else {
                newPrices.add(r.price);
              }
            }
          }
        }
      }
    }

    int? newRef = anchor ??
        (newPrices.isNotEmpty ? _upperMedian(newPrices) : null);
    int? usedRef = usedPrices.isNotEmpty ? _upperMedian(usedPrices) : null;

    // Estimasi depresiasi wajar 70% bila satu sisi kosong.
    if (usedRef == null && newRef != null) {
      usedRef = (newRef * 0.70).toInt();
    } else if (newRef == null && usedRef != null) {
      newRef = (usedRef / 0.70).toInt();
    }

    final refPrimary = newRef ?? usedRef ?? 0;
    return (refPrimary, newRef, usedRef);
  }

  /// Port endpoint POST /api/v1/analyze-bundle (main.py).
  /// Melempar BundleReferenceException sebagai padanan HTTP 422 Python.
  Future<BundleOutcome> analyzeBundle({
    required List<BundleInputItem> items,
    required int bundlePrice,
    String? condition = 'any',
  }) async {
    final breakdown = <BundleItemData>[];
    var newTotal = 0;
    var usedTotal = 0;
    final missing = <String>[];

    for (final item in items) {
      // Python: item.component_type or "cpu" (string kosong juga falsy).
      final ctype = (item.componentType == null || item.componentType!.isEmpty)
          ? 'cpu'
          : item.componentType!;
      final (refPrimary, newRef, usedRef) =
          await resolveBundleItemPrices(item.query, ctype);

      if (refPrimary <= 0) missing.add(item.query);

      // Python: (new_ref or ref_primary or 0) — 0 dianggap falsy.
      newTotal += (newRef != null && newRef != 0) ? newRef : refPrimary;
      usedTotal += (usedRef != null && usedRef != 0)
          ? usedRef
          : (refPrimary != 0 ? (refPrimary * 0.70).toInt() : 0);

      breakdown.add(BundleItemData(
        query: item.query,
        componentType: ctype,
        priceInput: item.price,
        referencePrice: refPrimary,
        newReferencePrice: newRef,
        usedReferencePrice: usedRef,
      ));
    }

    if (newTotal <= 0 && usedTotal <= 0) {
      throw BundleReferenceException(
        missing.isNotEmpty
            ? 'Harga referensi tidak ditemukan untuk: ${missing.join(', ')}'
            : 'Referensi tidak tersedia.',
      );
    }

    final referenceTotal = newTotal > 0 ? newTotal : usedTotal;

    final savingsPercent = referenceTotal > 0
        ? pyRound((1 - bundlePrice / referenceTotal) * 100, 1)
        : 0.0;
    final savingsUsedPercent = usedTotal > 0
        ? pyRound((1 - bundlePrice / usedTotal) * 100, 1)
        : null;

    final result = scorePrice(bundlePrice, [referenceTotal]);

    final newTotalStr = 'Rp${_grouped(newTotal)}';
    final usedTotalStr = 'Rp${_grouped(usedTotal)}';
    final bundleStr = 'Rp${_grouped(bundlePrice)}';

    final String rec;
    if (savingsPercent >= 10) {
      rec = 'Paket ini hemat $savingsPercent% dibeli bundling dibanding '
          'beli baru terpisah (total normal $newTotalStr). Worth it.';
    } else if (savingsPercent >= 0) {
      rec = 'Bundling ini hemat $savingsPercent% dibanding beli baru '
          'terpisah (total normal $newTotalStr). Masuk akal jika butuh '
          'semua komponennya.';
    } else {
      rec = 'Paket lebih mahal ${savingsPercent.abs()}% dibanding beli '
          'baru terpisah (total normal $newTotalStr). Pertimbangkan beli satuan.';
    }

    final crossMarketAdvice = '🏷️ Total Baru Retail: $newTotalStr '
        '(hemat $savingsPercent%) | '
        '📦 Total Estimasi Bekas: $usedTotalStr'
        '${savingsUsedPercent != null ? ' (hemat $savingsUsedPercent%)' : ''}'
        '. Tawaran paket seharga $bundleStr '
        '${(savingsUsedPercent != null && savingsUsedPercent != 0 && savingsUsedPercent > 0) ? 'sangat menarik karena di bawah harga total part bekas eceran!' : 'sesuai rentang pasar.'}';

    return BundleOutcome(
      bundlePrice: bundlePrice,
      referenceTotal: referenceTotal,
      newReferenceTotal: newTotal,
      usedReferenceTotal: usedTotal,
      score: result.score,
      verdict: result.verdict,
      recommendation: rec,
      savingsPercent: savingsPercent,
      savingsUsedPercent: savingsUsedPercent,
      crossMarketAdvice: crossMarketAdvice,
      items: breakdown,
    );
  }
}

// ---------------------------------------------------------------------------
// Helper laptop & cross-market (port fungsi privat analysis.py)
// ---------------------------------------------------------------------------

class _LaptopRow {
  String? brand;
  String? model;
  String? cpu;
  String? gpu;
  int? ramGb;
  int? storageGb;
  int price = 0;
  String? condition;
  String? source;
  String? listingUrl;
  DateTime? scrapedAt;
}

DateTime? _asDateTime(Object? v) {
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

List<_LaptopRow> _laptopRowsFromMaps(List<Map<String, Object?>> maps) => [
      for (final m in maps)
        _LaptopRow()
          ..brand = m['brand'] as String?
          ..model = m['model'] as String?
          ..cpu = m['cpu'] as String?
          ..gpu = m['gpu'] as String?
          ..ramGb = (m['ram_gb'] as num?)?.toInt()
          ..storageGb = (m['storage_gb'] as num?)?.toInt()
          ..price = (m['price'] as num?)?.toInt() ?? 0
          ..condition = m['condition'] as String?
          ..source = m['source'] as String?
          ..listingUrl = m['listing_url'] as String?
          ..scrapedAt = _asDateTime(m['scraped_at']),
    ];

/// Signature GPU ('RTX 4060 Ti' -> 'rtx4060ti'). Null kalau tidak disebut.
String? _gpuSig(String? text) {
  final m = RegExp(r'\b(rtx|gtx|rx)\s*(\d{3,4})\s*(ti|super|xt)?\b')
      .firstMatch((text ?? '').toLowerCase());
  return m != null ? '${m.group(1)}${m.group(2)}${m.group(3) ?? ''}' : null;
}

/// Signature CPU laptop ('Core i5-12450H' -> 'corei512450h').
String? _cpuSig(String? text) {
  final m = RegExp(
    r'\b(ryzen(?:\s*ai)?\s*[3579]|core\s*i[3579]|ultra\s*[579]|i[3579])\s*-?\s*(\d{4,5}[a-z]{0,3}|[a-z]{1,4}\d{3}[a-z]{0,3})?\b',
  ).firstMatch((text ?? '').toLowerCase());
  if (m == null) return null;
  var rawFam = m.group(1)!.replaceAll(RegExp(r'\s+'), '');
  if (RegExp(r'^i[3579]$').hasMatch(rawFam)) rawFam = 'core$rawFam';
  final num = m.group(2) ?? '';
  if (num.isEmpty) return null;
  return rawFam + num;
}

/// Tier CPU ('corei712700h' -> '7') utk pencocokan sekelas.
String? _cpuTier(String sig) {
  final m = RegExp(r'(?:corei|ryzen|ultra|ryzenai|i)([3579])').firstMatch(sig);
  return m?.group(1);
}

int? _extractStorageFromText(String? text) {
  final t = (text ?? '').toLowerCase();
  final mTb = RegExp(r'(\d)\s*tb\b').firstMatch(t);
  if (mTb != null) return int.parse(mTb.group(1)!) * 1000;
  final mSlash = RegExp(r'\b\d{1,2}\s*/\s*(\d{3,4})\b').firstMatch(t);
  if (mSlash != null) return int.parse(mSlash.group(1)!);
  final mSsd =
      RegExp(r'\b(128|256|512|1000|1024)\s*(?:gb)?\s*(?:ssd|nvme|storage|rom)?\b')
          .firstMatch(t);
  if (mSsd != null) return int.parse(mSsd.group(1)!);
  return null;
}

int? _extractRamFromText(String? text) {
  final t = (text ?? '').toLowerCase();
  final mRam = RegExp(r'\bram\s*(\d{1,2})\s*gb\b').firstMatch(t);
  if (mRam != null) return int.parse(mRam.group(1)!);
  final mDdr = RegExp(r'(\d{1,2})\s*gb\s*(?:ddr|ram|memory)\b').firstMatch(t);
  if (mDdr != null) return int.parse(mDdr.group(1)!);
  final mSlash = RegExp(r'\b(\d{1,2})\s*/\s*\d{3,4}\b').firstMatch(t);
  if (mSlash != null) return int.parse(mSlash.group(1)!);
  return null;
}

/// Port _generate_cross_market_advice() Python (string persis).
String? _generateCrossMarketAdvice({
  required String? condition,
  required int price,
  required int? newRef,
  required int? usedRef,
}) {
  final priceFmt = 'Rp${_grouped(price)}';
  final newFmt = newRef != null ? 'Rp${_grouped(newRef)}' : null;
  final usedFmt = usedRef != null ? 'Rp${_grouped(usedRef)}' : null;

  if (condition == 'new') {
    if (newRef != null && usedRef != null) {
      final pctSavings = pyRoundInt(((newRef - usedRef) / newRef) * 100);
      return '🏷️ Di pasar baru, median referensi adalah $newFmt. '
          '📦 Sebagai opsi alternatif, unit sekelas di pasar bekas beredar '
          'sekitar $usedFmt (hemat ~$pctSavings%). '
          'Dengan budget $priceFmt, di pasar bekas Anda juga berpotensi '
          'mendapatkan unit ber-tier performa lebih tinggi.';
    } else if (newRef != null) {
      return '🏷️ Di pasar baru, harga referensi retail terpantau di '
          'kisaran $newFmt.';
    } else if (usedRef != null) {
      return '📦 Data retail baru terbatas. Sebagai perbandingan, di '
          'pasar bekas beredar sekitar $usedFmt.';
    }
  } else if (condition == 'second') {
    if (usedRef != null && newRef != null) {
      if (price < newRef) {
        final pctSavings = pyRoundInt(((newRef - price) / newRef) * 100);
        return '📦 Di pasar bekas, harga referensi sekelas adalah '
            '$usedFmt. '
            '🏷️ Dibandingkan harga retail baru ($newFmt), tawaran bekas '
            'seharga $priceFmt menghemat sekitar $pctSavings%. '
            'Pastikan cek kesehatan fisik, suhu termal, dan fungsi '
            'komponen sebelum bertransaksi.';
      } else {
        return '📦 Di pasar bekas, harga referensi sekelas adalah '
            '$usedFmt. '
            '⚠️ Perhatian: tawaran bekas $priceFmt mendekati atau '
            'melebihi harga unit baru ($newFmt). '
            'Sangat disarankan membeli unit baru retail untuk jaminan '
            'garansi resmi.';
      }
    } else if (usedRef != null) {
      return '📦 Di pasar bekas, unit/komponen sekelas terpantau di '
          'kisaran $usedFmt.';
    } else if (newRef != null) {
      return '🏷️ Data pasar bekas terbatas. Sebagai perbandingan, unit '
          'baru di retail dibanderol sekitar $newFmt.';
    }
  } else {
    if (newRef != null && usedRef != null) {
      final pctSavings = pyRoundInt(((newRef - usedRef) / newRef) * 100);
      return '🏷️ Pasar Baru: referensi $newFmt | '
          '📦 Pasar Bekas: referensi $usedFmt (selisih ~$pctSavings%). '
          'Sesuaikan pilihan dengan prioritas garansi resmi vs '
          'efisiensi budget.';
    }
  }
  return null;
}
