// DRAFT — JANGAN PAKAI LANGSUNG. File ini BELUM diterapkan ke lib/.
//
// Dibuat di A4 (2026-10-24) sebagai persiapan Fase C: versi terbaru
// resolveCpuLaptop dari lib/services/engine/benchmark.dart dengan pola
// baru yang SAMA PERSIS dengan Python (tools/ml/train_price_models.py):
// bare iX, Core tanpa i, Ultra 3 digit, dan Apple kunci eksak.
//
// Cara pakai di Fase C: pindahkan isi fungsi resolveCpuLaptopDraft ke
// dalam class Benchmark (ganti resolveCpuLaptop lama), ganti parameter
// katalog dengan data.benchCatalog('cpu_mobile') / ('cpu'), dan ganti
// sort manual dengan stableSort yang sudah ada di scoring.dart.
// Catatan: engine saat ini hanya memakai entry hasil resolve; skrip
// latih juga memakai `full` (fallback cpu_sig). Bila Fase C ingin
// paritas penuh, teruskan full/tag ke pemanggil, jangan dibuang.
//
// Perbedaan disengaja vs method asli (agar file ini berdiri sendiri):
// - Input di-lowercase dulu (Python juga begitu); regex case-sensitive.
// - Guard 'octa-core'/'dual-core' dicek manual per match, bukan
//   lookbehind, karena lookbehind tidak portabel di semua RegExp Dart.
// - Katalog dilewat sebagai parameter, bukan data.benchCatalog.

typedef BenchEntry = Map<String, dynamic>;

String _sq(String? text) =>
    (text ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

num? _scoreOf(BenchEntry? entry) {
  final v = entry?['score'];
  return v is num && v > 0 ? v : null;
}

/// Regex lama (persis _cpuRe di benchmark.dart).
final _cpuRe = RegExp(
  r'\b(ryzen(?:\s*ai)?\s*[3579]|core\s*i[3579]|ultra\s*[579])\s*-?\s*(\d{4,5}[a-z]{0,3})\b',
);

/// Pola baru A4 (persis BARE_IX_RE / CORE_NO_I_RE / ULTRA_3_RE Python).
/// [1-9] di awal nomor menolak angka semu seperti '000'.
final _bareIxRe = RegExp(r'\bi([3579])\s*-?\s*([1-9]\d{3,4}[a-z]{0,3})\b');
final _coreNoIRe = RegExp(r'core\s*([579])\s*-?\s*([1-9]\d{2}[a-z]{0,3})\b');
final _ultra3Re = RegExp(r'ultra\s*([579])\s*-?\s*([1-9]\d{2}[a-z]{0,3})\b');
final _appleChipRe = RegExp(r'\bm([1234])\b');

/// Kunci Apple eksak (persis APPLE_*_KEYS Python). Dipakai hanya bila
/// kuncinya ADA di katalog — skor tidak pernah dikarang.
const _appleBaseKeys = <String, String>{
  '1': 'apple m1 8 core 3200 mhz',
  '2': 'apple m2 8 core 3500 mhz',
  '3': 'apple m3 8 core',
  '4': 'apple m4 10 core',
};
const _appleProKeys = <String, String>{
  '1': 'apple m1 pro 10 core 3200 mhz',
  '2': 'apple m2 pro 10 core 3480 mhz',
  '3': 'apple m3 pro 11 core',
  '4': 'apple m4 pro 12 core',
};
const _appleMaxKeys = <String, String>{
  '1': 'apple m1 max 10 core 3200 mhz',
  '2': 'apple m2 max 12 core 3680 mhz',
  '3': 'apple m3 max 14 core',
  '4': 'apple m4 max 14 core',
};

/// True bila match pada [start] tidak didahului huruf/hyphen (menolak
/// 'octa-core', 'dual-core', 'quad-core'). Pengganti lookbehind
/// (?<![a-z-]) di Python.
bool _cleanStart(String low, int start) {
  if (start == 0) return true;
  final prev = low[start - 1];
  return !(RegExp(r'[a-z-]').hasMatch(prev));
}

/// Pola baru -> (full kanonik, tag), atau null. Urutan: bare iX,
/// Core tanpa i, Ultra 3 digit. Persis _new_cpu_full Python.
(String, String)? _newCpuFull(String low) {
  for (final m in _bareIxRe.allMatches(low)) {
    return ('core i${m.group(1)} ${m.group(2)}', 'bare_ix');
  }
  for (final m in _coreNoIRe.allMatches(low)) {
    if (!_cleanStart(low, m.start)) continue;
    return ('core ${m.group(1)} ${m.group(2)}', 'core_no_i');
  }
  for (final m in _ultra3Re.allMatches(low)) {
    if (!_cleanStart(low, m.start)) continue;
    return ('ultra ${m.group(1)} ${m.group(2)}', 'ultra_3');
  }
  return null;
}

/// Entri Apple eksak, atau null. Persis _apple_cpu_entry Python:
/// butuh konteks apple/macbook; kualifikasi pro/max hanya bila langsung
/// mengikuti chip; 'M2 2280'/'2230' (ukuran SSD) selalu dilewati.
({BenchEntry entry, String key})? _appleCpuEntry(
  String low,
  Map<String, dynamic> mobile,
  Map<String, dynamic> desktop,
) {
  if (!low.contains('apple') &&
      !low.contains('macbook') &&
      !low.contains('mac book')) {
    return null;
  }
  final m = _appleChipRe.firstMatch(low);
  if (m == null) return null;
  final tail = low.substring(m.end);
  if (RegExp(r'^\s+22[38]0\b').hasMatch(tail)) return null;
  final table = RegExp(r'^\s+max\b').hasMatch(tail)
      ? _appleMaxKeys
      : RegExp(r'^\s+pro\b').hasMatch(tail)
          ? _appleProKeys
          : _appleBaseKeys;
  final key = table[m.group(1)];
  if (key == null) return null;
  for (final cat in <Map<String, dynamic>>[mobile, desktop]) {
    final entry = cat[key];
    if (entry is Map && _scoreOf(entry.cast<String, dynamic>()) != null) {
      return (entry: entry.cast<String, dynamic>(), key: key);
    }
  }
  return null;
}

/// Hasil resolve: entry katalog (null bila tidak cocok), full kanonik
/// (null bila tidak ada pola), dan tag ('old', 'bare_ix', 'core_no_i',
/// 'ultra_3', 'apple', 'none').
({BenchEntry? entry, String? full, String tag}) resolveCpuLaptopDraft(
  String? text,
  Map<String, dynamic> cpuMobile,
  Map<String, dynamic> cpuDesktop,
) {
  final low = (text ?? '').toLowerCase();
  final m = _cpuRe.firstMatch(low);
  late final String full;
  late final String tag;
  late final String numRaw;
  if (m != null) {
    full = m.group(0)!;
    tag = 'old';
    numRaw = m.group(2)!;
  } else {
    final nw = _newCpuFull(low);
    if (nw == null) {
      final ap = _appleCpuEntry(low, cpuMobile, cpuDesktop);
      if (ap == null) return (entry: null, full: null, tag: 'none');
      return (entry: ap.entry, full: ap.key, tag: 'apple');
    }
    full = nw.$1;
    tag = nw.$2;
    numRaw = RegExp(r'(\d+[a-z]{0,3})$').firstMatch(full)!.group(1)!;
  }

  BenchEntry? bestIn(Map<String, dynamic> cat) {
    final qsq = _sq(full);
    BenchEntry? best;
    var bestNameLen = 0;
    for (final e in cat.entries) {
      final entry = e.value;
      if (entry is! Map) continue;
      final ksq = _sq(e.key);
      if (qsq.isNotEmpty && (ksq.contains(qsq) || qsq.contains(ksq))) {
        final nameLen =
            _sq((entry['name'] as String? ?? '').toLowerCase()).length;
        if (best == null || ksq.length < bestNameLen) {
          best = entry.cast<String, dynamic>();
          bestNameLen = nameLen;
        }
      }
    }
    return best;
  }

  // 0) katalog MOBILE, lalu 1) katalog desktop (sama seperti asli).
  final bestM = bestIn(cpuMobile);
  if (bestM != null) return (entry: bestM, full: full, tag: tag);
  final best = bestIn(cpuDesktop);
  if (best != null) return (entry: best, full: full, tag: tag);

  // 2) proksi: famili+tier sama, nomor terdekat (sama seperti asli).
  // Catatan: proksi tidak menjangkau kunci 3 digit Core/Ultra karena
  // _cpuRe kunci juga menuntut 4-5 digit — sama seperti Python.
  final tier = RegExp(r'(i[3579]|[3579])').firstMatch(full);
  if (tier == null) return (entry: null, full: full, tag: 'none');
  final tierStr = tier.group(1)!;
  final tierCh = tierStr[tierStr.length - 1];
  final isIntel = full.contains('core') || full.contains('ultra');
  final wantNumStr = numRaw.replaceAll(RegExp(r'[a-z]+$'), '');
  if (!RegExp(r'^\d+$').hasMatch(wantNumStr)) {
    return (entry: null, full: full, tag: 'none');
  }
  final wantNum = int.parse(wantNumStr);

  int? candNum(String key) {
    final cm = _cpuRe.firstMatch(key.toLowerCase());
    if (cm == null) return null;
    final kfull = cm.group(0)!;
    final ktier = RegExp(r'(i[3579]|[3579])').firstMatch(kfull);
    if (ktier == null) return null;
    final ktierStr = ktier.group(1)!;
    if (ktierStr[ktierStr.length - 1] != tierCh) return null;
    final kintel = kfull.contains('core') || kfull.contains('ultra');
    if (kintel != isIntel) return null;
    final knum = cm.group(2)!.replaceAll(RegExp(r'[a-z]+$'), '');
    if (!RegExp(r'^\d+$').hasMatch(knum)) return null;
    return int.parse(knum);
  }

  final pool = <(int, String, BenchEntry)>[];
  for (final e in cpuDesktop.entries) {
    final entry = e.value;
    if (entry is! Map) continue;
    final knum = candNum(e.key);
    if (knum != null) {
      pool.add(( (knum - wantNum).abs(), e.key, entry.cast<String, dynamic>()));
    }
  }
  if (pool.isEmpty) return (entry: null, full: full, tag: 'none');
  pool.sort((a, b) {
    final byDiff = a.$1.compareTo(b.$1);
    if (byDiff != 0) return byDiff;
    return _sq(a.$2).length.compareTo(_sq(b.$2).length);
  });
  return (entry: pool[0].$3, full: full, tag: tag);
}
