import 'dataset.dart';
import 'scoring.dart';

/// Port setia services/benchmark.py (repo lama): resolver skor benchmark
/// PassMark + konsensus multi-sumber + advice "di harga segitu lebih
/// baik X". Entri katalog dipertahankan sebagai Map persis JSON asalnya
/// (mirror dict Python: name, score, price_usd, ...).

typedef BenchEntry = Map<String, dynamic>;

String _sq(String? text) =>
    (text ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

num? _numOf(BenchEntry? entry, String key) {
  final v = entry?[key];
  return v is num ? v : null;
}

class Benchmark {
  const Benchmark(this.data);

  final BenchmarkData data;

  Map<String, dynamic> _catalog(String? componentType) =>
      componentType == null ? <String, dynamic>{} : data.benchCatalog(componentType);

  Map<String, dynamic> _consensusCatalogOf(String? componentType) =>
      componentType == null
          ? <String, dynamic>{}
          : data.consensusCatalog(componentType);

  /// Port passmark_score(): entri PassMark utk model di query.
  /// Null kalau bukan gpu/cpu / tak ketemu.
  BenchEntry? passmarkScore(String query, String? componentType) {
    if (componentType != 'gpu' && componentType != 'cpu') return null;
    final text = (query).toLowerCase();
    final catalog = _catalog(componentType);
    if (catalog.isEmpty) return null;

    // 1) exact key ("rtx 4060 ti" -> "geforce rtx 4060 ti" dsb.)
    for (final probe in <String>[
      'geforce $text',
      'radeon $text',
      'nvidia $text',
      'amd $text',
      text,
    ]) {
      final key = probe.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).join(' ');
      final entry = catalog[key];
      if (entry is Map) return entry.cast<String, dynamic>();
    }

    // 2) substring dua arah via squash ('ryzen5 5600x' == 'ryzen 5 5600x')
    // Python `qsq in ksq or ksq in qsq`; String.contains('') di Dart
    // juga true seperti `in` di Python, jadi semantiknya sama persis.
    final qsq = _sq(text);
    BenchEntry? best;
    var bestNameLen = 0;
    for (final e in catalog.entries) {
      final entry = e.value;
      if (entry is! Map) continue;
      final ksq = _sq(e.key);
      if (ksq.contains(qsq) || qsq.contains(ksq)) {
        // Ambil yang pendek (paling spesifik) — Python membandingkan
        // panjang kunci baru vs panjang NAMA entri terbaik saat ini.
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

  /// Port extract_vram_gb().
  int? extractVramGb(String? text) {
    final textLow = (text ?? '').toLowerCase();
    final m = RegExp(r'\b(\d{1,2})\s*gb\b').firstMatch(textLow);
    if (m != null) {
      final val = int.parse(m.group(1)!);
      if (<int>{2, 3, 4, 6, 8, 10, 11, 12, 16, 20, 24}.contains(val)) {
        return val;
      }
    }
    if (textLow.contains('rtx 3060') && !textLow.contains('ti')) return 12;
    if (textLow.contains('rx 6700 xt') || textLow.contains('rx 6750 xt')) {
      return 12;
    }
    if (textLow.contains('rx 6800')) return 16;
    if (textLow.contains('rtx 4070')) return 12;
    if (textLow.contains('rtx 4060') ||
        textLow.contains('rx 6600') ||
        textLow.contains('rtx 3050') ||
        textLow.contains('rtx 2060 super')) {
      return 8;
    }
    if (textLow.contains('gtx 1660') || textLow.contains('rtx 2060')) {
      return 6;
    }
    if (textLow.contains('gtx 1650')) return 4;
    return null;
  }

  /// Port get_tier_label().
  String getTierLabel(num? score, String? componentType) {
    if (score == null || score == 0) return 'Standard';
    if (componentType == 'gpu') {
      if (score >= 26000) return 'Enthusiast (4K Ultra Gaming)';
      if (score >= 19000) return 'High End (1440p Ultra)';
      if (score >= 13000) return 'Midrange (1080p Ultra / 1440p Mid)';
      if (score >= 7000) return 'Entry Level (1080p Esports)';
      return 'Basic (Office & Casual)';
    } else if (componentType == 'cpu') {
      if (score >= 32000) return 'High End (Heavy Productivity & Gaming)';
      if (score >= 19000) return 'Midrange (Solid Gaming & Multitasking)';
      if (score >= 11000) return 'Budget (1080p Gaming & Daily Work)';
      return 'Entry Level (Office & Casual)';
    } else if (componentType == 'laptop') {
      if (score >= 20000) return 'High End Gaming / Workstation';
      if (score >= 13000) return 'Midrange Gaming / Content Creation';
      if (score >= 7500) return 'Budget Gaming / Fast Productivity';
      return 'Ultrabook / Daily Office';
    }
    return 'Standard';
  }

  /// Port better_alternatives(): kandidat sekelas dgn performa/harga
  /// lebih baik dr harga penawaran user, berdasar skor PassMark.
  List<Map<String, Object?>> betterAlternatives(
    String query,
    String? componentType,
    int priceIdr,
    double usdToIdr, {
    int maxResults = 2,
  }) {
    final base = passmarkScore(query, componentType);
    if (base == null || priceIdr == 0) return [];
    final baseScore = _numOf(base, 'score');
    if (baseScore == null) return [];
    final minScore = baseScore * 1.15;
    final baseVram = componentType == 'gpu' ? extractVramGb(query) : null;

    var pool = <BenchEntry>[
      for (final e in _catalog(componentType).values)
        if (e is Map &&
            (_numOf(e.cast<String, dynamic>(), 'score') ?? -1) >= minScore &&
            _truthyPrice(e.cast<String, dynamic>()))
          e.cast<String, dynamic>(),
    ];
    bool withinBudget(BenchEntry e) =>
        (_numOf(e, 'price_usd') ?? 0) * usdToIdr * 1.10 <= priceIdr;
    pool = pool.where(withinBudget).toList();

    // Prioritaskan kandidat yang kapasitas VRAM-nya tidak downgrade
    // jika user punya VRAM besar.
    if (baseVram != null && baseVram >= 12) {
      final vramKept = pool
          .where((e) => (extractVramGb(e['name'] as String? ?? '') ?? 0) >= baseVram)
          .toList();
      if (vramKept.isNotEmpty) pool = vramKept;
    }

    // Pilih performa tertinggi yang masih masuk budget; harga tie-breaker.
    stableSort(pool, (a, b) {
      final byScore =
          (_numOf(b, 'score') ?? 0).compareTo(_numOf(a, 'score') ?? 0);
      if (byScore != 0) return byScore;
      return (_numOf(a, 'price_usd') ?? 0)
          .compareTo(_numOf(b, 'price_usd') ?? 0);
    });

    return [
      for (final entry in pool.take(maxResults))
        <String, Object?>{
          'name': entry['name'],
          'score': _numOf(entry, 'score')?.toInt(),
          'est_price_idr':
              ((_numOf(entry, 'price_usd') ?? 0) * usdToIdr * 1.10).toInt(),
          'gain_percent':
              pyRoundInt(((_numOf(entry, 'score') ?? 0) / baseScore - 1) * 100),
          'vram_gb': componentType == 'gpu'
              ? extractVramGb(entry['name'] as String? ?? '')
              : null,
          'tier_label': getTierLabel(_numOf(entry, 'score'), componentType),
        },
    ];
  }

  bool _truthyPrice(BenchEntry e) {
    final p = _numOf(e, 'price_usd');
    return p != null && p != 0;
  }

  // ---------------- Laptop: skor combo GPU+CPU ----------------

  static final RegExp _cpuRe = RegExp(
    r'\b(ryzen(?:\s*ai)?\s*[3579]|core\s*i[3579]|ultra\s*[579])\s*-?\s*(\d{4,5}[a-z]{0,3})\b',
    caseSensitive: false,
  );

  /// Port resolve_cpu_laptop(): CPU laptop -> entri PassMark (katalog
  /// mobile persis, lalu desktop, lalu proksi famili+tier terdekat).
  BenchEntry? resolveCpuLaptop(String? text) {
    final m = _cpuRe.firstMatch(text ?? '');
    if (m == null) return null;
    final full = m.group(0)!.toLowerCase();
    final catalog = data.benchCatalog('cpu');
    final mobile = data.benchCatalog('cpu_mobile');

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

    // 0) katalog MOBILE persis (PassMark punya data CPU laptop sendiri)
    final bestM = bestIn(mobile);
    if (bestM != null) return bestM;

    // 1) nama persis / substring di katalog desktop via squash
    final best = bestIn(catalog);
    if (best != null) return best;

    // 2) proksi: famili+tier sama, nomor terdekat
    final tier = RegExp(r'(i[3579]|[3579])').firstMatch(full);
    if (tier == null) return null;
    final tierCh = tier.group(1)![tier.group(1)!.length - 1];
    final isIntel = full.contains('core') || full.contains('ultra');
    final wantNumStr =
        m.group(2)!.toLowerCase().replaceAll(RegExp(r'[a-z]+$'), '');
    if (!RegExp(r'^\d+$').hasMatch(wantNumStr)) return null;
    final wantNum = int.parse(wantNumStr);

    int? candNum(String key) {
      final cm = _cpuRe.firstMatch(key);
      if (cm == null) return null;
      final kfull = cm.group(0)!.toLowerCase();
      final ktier = RegExp(r'(i[3579]|[3579])').firstMatch(kfull);
      if (ktier == null) return null;
      if (ktier.group(1)![ktier.group(1)!.length - 1] != tierCh) return null;
      final kintel = kfull.contains('core') || kfull.contains('ultra');
      if (kintel != isIntel) return null;
      final knum = cm.group(2)!.replaceAll(RegExp(r'[a-z]+$'), '');
      if (!RegExp(r'^\d+$').hasMatch(knum)) return null;
      return int.parse(knum);
    }

    final pool = <(int, String, BenchEntry)>[];
    for (final e in catalog.entries) {
      final entry = e.value;
      if (entry is! Map) continue;
      final knum = candNum(e.key);
      if (knum != null) {
        pool.add(((knum - wantNum).abs(), e.key, entry.cast<String, dynamic>()));
      }
    }
    if (pool.isEmpty) return null;
    stableSort(pool, (a, b) {
      final byDiff = a.$1.compareTo(b.$1);
      if (byDiff != 0) return byDiff;
      return _sq(a.$2).length.compareTo(_sq(b.$2).length);
    });
    return pool[0].$3;
  }

  bool _isIntegratedGpu(String? gpuText) {
    if (gpuText == null) return true;
    final low = gpuText.toLowerCase().trim();
    if (low.isEmpty) return true;
    const igpuTokens = [
      'iris', 'uhd', 'hd graphics', 'vega', 'radeon graphics',
      'integrated', 'shared', 'intel graphics', 'intel hd',
      'apple', 'm1', 'm2', 'm3', 'm4', 'snapdragon', 'adreno',
    ];
    return igpuTokens.any((tok) => low.contains(tok));
  }

  /// Port laptop_combo_score(): skor gabungan unit laptop.
  /// Gaming (dGPU): GPU 65% + CPU 35%. iGPU: CPU 75% + GPU 25%.
  Map<String, Object?>? laptopComboScore(String? cpuText, String? gpuText) {
    final gpuEntry =
        gpuText != null ? passmarkScore(gpuText, 'gpu') : null;
    final cpuEntry = cpuText != null ? resolveCpuLaptop(cpuText) : null;
    final gscore = _numOf(gpuEntry, 'score');
    final cscore = _numOf(cpuEntry, 'score');
    final isIgpu = _isIntegratedGpu(gpuText);

    late final double combo;
    if (isIgpu) {
      if (cscore != null && cscore != 0 && gscore != null && gscore != 0) {
        combo = 0.75 * cscore + 0.25 * gscore;
      } else if (cscore != null && cscore != 0) {
        combo = cscore.toDouble();
      } else if (gscore != null && gscore != 0) {
        combo = gscore.toDouble();
      } else {
        return null;
      }
    } else {
      if (gscore != null && gscore != 0 && cscore != null && cscore != 0) {
        combo = 0.65 * gscore + 0.35 * cscore;
      } else if ((gscore != null && gscore != 0) ||
          (cscore != null && cscore != 0)) {
        combo = (gscore ?? cscore)!.toDouble();
      } else {
        return null;
      }
    }

    final scoreVal = pyRoundInt(combo);
    return <String, Object?>{
      'gpu': gpuEntry,
      'cpu': cpuEntry,
      'score': scoreVal,
      'is_igpu': isIgpu,
      'tier_label': getTierLabel(scoreVal, 'laptop'),
    };
  }

  // ---------------------------------------------------------------------
  // Konsensus multi-sumber (2026-10-15): skor 0-100 dari rata-rata
  // percentile equal-weight antar sumber benchmark.
  // Diutamakan di atas skor PassMark tunggal bila tersedia.
  // ---------------------------------------------------------------------

  /// Port consensus_lookup(): entri konsensus utk model di query.
  BenchEntry? consensusLookup(String query, String? componentType) {
    if (componentType != 'gpu' && componentType != 'cpu') return null;
    final text = query.toLowerCase();
    final catalog = _consensusCatalogOf(componentType);
    if (catalog.isEmpty) return null;

    for (final probe in <String>[
      'geforce $text',
      'radeon $text',
      'nvidia $text',
      'amd $text',
      text,
    ]) {
      final key = probe.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).join(' ');
      final entry = catalog[key];
      if (entry is Map) return entry.cast<String, dynamic>();
    }

    final qsq = _sq(text);
    BenchEntry? best;
    var bestNameLen = 0;
    for (final e in catalog.entries) {
      final entry = e.value;
      if (entry is! Map) continue;
      final ksq = _sq(e.key);
      if (ksq.contains(qsq) || qsq.contains(ksq)) {
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

  /// Port consensus_tier_label().
  String consensusTierLabel(num? score) {
    if (score == null) return 'Standard';
    if (score >= 80) return 'Kelas Atas (High End)';
    if (score >= 60) return 'Menengah Atas (Upper Midrange)';
    if (score >= 40) return 'Menengah (Midrange)';
    if (score >= 20) return 'Pemula (Entry Level)';
    return 'Dasar (Basic)';
  }

  /// Port better_alternatives_consensus(): kandidat berdasar skor
  /// KONSENSUS (0-100). Syarat: skor >= 10 poin di atas user DAN
  /// estimasi harga <= penawaran.
  List<Map<String, Object?>> betterAlternativesConsensus(
    String query,
    String? componentType,
    int priceIdr,
    double usdToIdr, {
    int maxResults = 2,
  }) {
    final base = consensusLookup(query, componentType);
    if (base == null || priceIdr == 0) return [];
    final baseScore = _numOf(base, 'consensus_score');
    if (baseScore == null) return [];
    final minScore = baseScore + 10;
    final baseVram = componentType == 'gpu' ? extractVramGb(query) : null;

    var pool = <BenchEntry>[
      for (final e in _consensusCatalogOf(componentType).values)
        if (e is Map &&
            (_numOf(e.cast<String, dynamic>(), 'consensus_score') ?? -1) >=
                minScore &&
            _truthyPrice(e.cast<String, dynamic>()) &&
            (_numOf(e.cast<String, dynamic>(), 'price_usd') ?? 0) *
                    usdToIdr *
                    1.10 <=
                priceIdr)
          e.cast<String, dynamic>(),
    ];

    if (baseVram != null && baseVram >= 12) {
      final vramKept = pool
          .where((e) => (extractVramGb(e['name'] as String? ?? '') ?? 0) >= baseVram)
          .toList();
      if (vramKept.isNotEmpty) pool = vramKept;
    }

    stableSort(pool, (a, b) {
      final byScore = (_numOf(b, 'consensus_score') ?? 0)
          .compareTo(_numOf(a, 'consensus_score') ?? 0);
      if (byScore != 0) return byScore;
      return (_numOf(a, 'price_usd') ?? 0)
          .compareTo(_numOf(b, 'price_usd') ?? 0);
    });

    final out = <Map<String, Object?>>[];
    for (final e in pool.take(maxResults)) {
      var gainPct = 0;
      if (baseScore > 0) {
        gainPct =
            pyRoundInt(((_numOf(e, 'consensus_score') ?? 0) / baseScore - 1) * 100);
      }
      out.add(<String, Object?>{
        'name': e['name'],
        'score': pyRoundInt((_numOf(e, 'consensus_score') ?? 0).toDouble()),
        'est_price_idr': ((_numOf(e, 'price_usd') ?? 0) * usdToIdr * 1.10).toInt(),
        'gain_percent': gainPct,
        'vram_gb': componentType == 'gpu'
            ? extractVramGb(e['name'] as String? ?? '')
            : null,
        'tier_label': consensusTierLabel(_numOf(e, 'consensus_score')),
        'n_sources': e['n_sources'],
        'score_source': 'consensus',
      });
    }
    return out;
  }
}
