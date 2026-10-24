/// Model regresi harga wajar (Fase C, 2026-10-24).
///
/// Port jalur prediksi `tools/ml/train_price_models.py` (Fase B final,
/// `assets/data/price_models.json`) ke Dart. Modul ini TIDAK mengubah
/// gerbang: `enabled`/`enabled_fallback` dibaca apa adanya dari JSON,
/// dan pemakaian model diputuskan di `AnalysisEngine` (pembanding < 5).
///
/// Konvensi port:
/// - Nama fitur PERSIS dari JSON (`ln_passmark`, `vram_gb`, ...).
/// - Prediksi = exp(intercept + jumlah coef x fitur), koefisien mentah
///   (Python sudah mengekspor skala mentah; JANGAN menstandardisasi ulang).
/// - Rentang = [exp(mu - 0.67 x sigma), exp(mu + 0.67 x sigma)] dengan
///   sigma = sigma_log JSON, dilabel "rentang perkiraan" di UI.
/// - Katalog PassMark diakses lewat `Benchmark` yang sudah ada; TIDAK
///   ada file asset baru.
///
/// Kesenjangan yang didokumentasikan (bukan disembunyikan):
/// - VRAM: Python mengimputasi median PER MODEL, JSON final hanya memuat
///   median kategori (`defaults['vram_gb']` = 8.0). Dart memakai median
///   kategori bila VRAM tak ter-parse. Dari 5 kasus fixture gpu, 0 kasus
///   terdampak (semuanya punya VRAM mentah).
/// - Kondisi listing TIDAK diinferensi di Dart (inferensi Tokopedia dari
///   judul hanya ada di pipeline latih Python); kondisi app berasal dari
///   pilihan user (`any`/`baru`/`bekas`).
library;

import 'dart:math' as math;

import 'benchmark.dart';

/// Satu kategori model dari `price_models.json`.
class MlCategoryModel {
  const MlCategoryModel({
    required this.enabled,
    required this.enabledFallback,
    required this.intercept,
    required this.features,
    required this.defaults,
    required this.sigmaLog,
  });

  /// Tier 1 — selalu false di JSON final (dinonaktifkan A5).
  final bool enabled;

  /// Tier 2 fallback — true hanya gpu/cpu/ram/laptop di JSON final.
  final bool enabledFallback;

  final double intercept;

  /// Nama fitur -> koefisien mentah, urutan = urutan list JSON.
  final Map<String, double> features;

  /// Nilai default/imputasi per kategori (median kategori, rata-rata
  /// dummy kondisi, median speed per-DDR).
  final Map<String, double> defaults;

  final double sigmaLog;

  factory MlCategoryModel.fromJson(Map<String, dynamic> json) {
    final feats = <String, double>{};
    final fl = json['features'];
    if (fl is List) {
      for (final f in fl) {
        if (f is Map && f['name'] is String && f['coef'] is num) {
          feats[f['name'] as String] = (f['coef'] as num).toDouble();
        }
      }
    }
    final defs = <String, double>{};
    final d = json['defaults'];
    if (d is Map) {
      d.forEach((k, v) {
        if (v is num) defs[k as String] = v.toDouble();
      });
    }
    return MlCategoryModel(
      enabled: json['enabled'] == true,
      enabledFallback: json['enabled_fallback'] == true,
      intercept: (json['intercept'] as num?)?.toDouble() ?? 0.0,
      features: feats,
      defaults: defs,
      sigmaLog: (json['sigma_log'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Seluruh model dari `assets/data/price_models.json`.
class MlPriceModels {
  const MlPriceModels(this.categories);

  final Map<String, MlCategoryModel> categories;

  factory MlPriceModels.fromJson(Map<String, dynamic> json) {
    final cats = <String, MlCategoryModel>{};
    final c = json['categories'];
    if (c is Map) {
      c.forEach((k, v) {
        if (v is Map) {
          cats[k as String] = MlCategoryModel.fromJson(
            v.cast<String, dynamic>(),
          );
        }
      });
    }
    return MlPriceModels(cats);
  }

  MlCategoryModel? category(String name) => categories[name];

  bool isFallbackEnabled(String name) =>
      categories[name]?.enabledFallback == true;

  /// Prediksi mentah (TANPA gerbang): null bila kategori tak dikenal
  /// atau ada fitur model yang hilang/tak hingga.
  ({double price, double low, double high})? predict(
    String category,
    Map<String, double> features,
  ) {
    final model = categories[category];
    if (model == null) return null;
    var mu = model.intercept;
    for (final entry in model.features.entries) {
      final v = features[entry.key];
      if (v == null || !v.isFinite) return null;
      mu += entry.value * v;
    }
    if (!mu.isFinite) return null;
    return (
      price: math.exp(mu),
      low: math.exp(mu - 0.67 * model.sigmaLog),
      high: math.exp(mu + 0.67 * model.sigmaLog),
    );
  }
}

/// Pemetaan kondisi — SATU fungsi (port `resolve_condition_dummies`
/// Python untuk sisi pemakaian): 'baru'/'new' -> (1,0); 'bekas'/'second'
/// -> (0,1); 'any'/unknown/kosong -> rata-rata dummy dari defaults JSON.
(double, double) mlConditionDummies(
  String? condition,
  MlCategoryModel model,
) {
  final c = (condition ?? '').toLowerCase();
  if (c == 'baru' || c == 'new') return (1.0, 0.0);
  if (c == 'bekas' || c == 'second') return (0.0, 1.0);
  return (
    model.defaults['cond_new_mean'] ?? 0.0,
    model.defaults['cond_second_mean'] ?? 0.0,
  );
}

// ---------------------------------------------------------------------------
// Ekstraktor teks — port fungsi Python (nama Python di komentar).
// Semua menerima teks apa adanya dan me-lowercase sendiri, seperti Python.
// ---------------------------------------------------------------------------

/// Port `extract_gpu_model`: token GPU berspasi dari GPU_RE, atau null.
String? mlExtractGpuModel(String? text) {
  final m = RegExp(r'\b(rtx|gtx|rx|arc)\s*([ab]?\d{3,4})\s*(ti|super|xt)?\b')
      .firstMatch((text ?? '').toLowerCase());
  if (m == null) return null;
  var out = '${m.group(1)} ${m.group(2)}';
  final suffix = m.group(3);
  if (suffix != null) out += ' $suffix';
  return out;
}

/// Port `extract_cpu_model`: token CPU berspasi dari CPU_MODEL_RE, atau null.
String? mlExtractCpuModel(String? text) {
  final m = RegExp(
    r'\b(ryzen\s*[3579]|core\s*i[3579])\s*-?\s*(\d{4,5})([a-z]{0,2})?\b',
  ).firstMatch((text ?? '').toLowerCase());
  if (m == null) return null;
  final tier = RegExp(r'[3579]').firstMatch(m.group(1)!)!.group(0)!;
  final suffix = m.group(3) ?? '';
  if (m.group(1)!.contains('ryzen')) {
    return 'ryzen $tier ${m.group(2)}$suffix';
  }
  return 'core i$tier ${m.group(2)}$suffix';
}

/// Port `gpu_sig` (GPU_SIG_RE, tanpa arc): signature padat, atau null.
/// Dipakai untuk deteksi dGPU laptop — arc TIDAK dihitung dGPU (Python).
String? mlGpuSig(String? text) {
  final m = RegExp(r'\b(rtx|gtx|rx)\s*(\d{3,4})\s*(ti|super|xt)?\b')
      .firstMatch((text ?? '').toLowerCase());
  if (m == null) return null;
  return '${m.group(1)}${m.group(2)}${m.group(3) ?? ''}';
}

/// Port `extract_ram_cat`: (total GB, DDR, speed MHz, sodimm 0/1).
/// Total null bila tak ditemukan; kit NxM dijumlah (2x4GB -> 8).
(int?, int?, int?, int) mlExtractRamCat(String? text) {
  final t = (text ?? '').toLowerCase();
  int? total;
  final kit =
      RegExp(r'(\d)\s*x\s*(\d{1,2}(?:[.,]\d+)?)\s*gb\b').firstMatch(t);
  if (kit != null) {
    total = int.parse(kit.group(1)!) *
        double.parse(kit.group(2)!.replaceAll(',', '.')).round();
  } else {
    final plain =
        RegExp(r'(\d{1,2}(?:[.,]\d+)?)\s*gb\b').firstMatch(t);
    if (plain != null) {
      total =
          double.parse(plain.group(1)!.replaceAll(',', '.')).round();
    }
  }
  final ddrM = RegExp(r'ddr\s*([345])').firstMatch(t);
  final ddr = ddrM == null ? null : int.parse(ddrM.group(1)!);
  final speedM = RegExp(r'(\d{3,4})\s*mhz\b').firstMatch(t);
  final speed = speedM == null ? null : int.parse(speedM.group(1)!);
  final sodimm = t.replaceAll('-', '').contains('sodimm') ? 1 : 0;
  return (total, ddr, speed, sodimm);
}

/// Port `classify_storage_type` (Fase A2): 'nvme' / 'sata_ssd' / 'hdd',
/// atau null = DROP. Urutan: nvme/pcie (negation-aware) > sata eksplisit
/// > m.2 saja DROP > ssd -> sata_ssd > hdd > drop.
String? mlClassifyStorageType(String? text) {
  final t = (text ?? '').toLowerCase();
  final clean = t.replaceAll(
    RegExp(r'\b(bukan|non|no|tanpa)[\s\-]+(nvme|pcie|sata)\b'),
    ' ',
  );
  if (RegExp(r'\bnvme\b|\bpcie\b').hasMatch(clean)) return 'nvme';
  if (RegExp(r'\bsata\b').hasMatch(clean)) return 'sata_ssd';
  if (RegExp(r'\bm\.?2\b').hasMatch(clean)) return null;
  if (RegExp(r'\bssd\b').hasMatch(clean)) return 'sata_ssd';
  if (RegExp(r'\bhdd\b|\bharddisk\b|\bhardisk\b').hasMatch(clean)) {
    return 'hdd';
  }
  return null;
}

double? _parseDecimal(String raw) {
  final v = double.tryParse(raw.replaceAll(',', '.'));
  return v;
}

/// Port `extract_storage_cat`: (kapasitas GB, tipe). Kapasitas <= 0
/// diperlakukan tak ter-parse (null), bukan crash log(0). Desimal TB
/// didukung: '2.0TB' -> 2000 (perbaikan A4 atas bug baca 0TB).
(int?, String?) mlExtractStorageCat(String? text) {
  final t = (text ?? '').toLowerCase();
  int? cap;
  final tb = RegExp(r'(\d+(?:[.,]\d+)?)\s*tb\b').firstMatch(t);
  if (tb != null) {
    cap = (_parseDecimal(tb.group(1)!)! * 1000).round();
  } else {
    final gb =
        RegExp(r'(\d{1,4}(?:[.,]\d+)?)\s*gb\b').firstMatch(t);
    if (gb != null) cap = _parseDecimal(gb.group(1)!)!.round();
  }
  if (cap != null && cap <= 0) cap = null;
  return (cap, mlClassifyStorageType(t));
}

/// Port `extract_storage_text` (laptop): kapasitas GB saja, atau null.
/// Sama dengan `_extractStorageFromText` yang sudah diperbaiki desimalnya;
/// kapasitas <= 0 -> null (Python membuang baris sto <= 0).
int? mlExtractStorageText(String? text) {
  final t = (text ?? '').toLowerCase();
  final tb = RegExp(r'(\d+(?:[.,]\d+)?)\s*tb\b').firstMatch(t);
  if (tb != null) {
    final cap = (_parseDecimal(tb.group(1)!)! * 1000).round();
    return cap <= 0 ? null : cap;
  }
  final slash =
      RegExp(r'\b\d{1,2}\s*/\s*(\d{3,4})\b').firstMatch(t);
  if (slash != null) return int.parse(slash.group(1)!);
  final fixed = RegExp(
    r'\b(128|256|512|1000|1024)\s*(?:gb)?\s*(?:ssd|nvme|storage|rom)?\b',
  ).firstMatch(t);
  if (fixed != null) return int.parse(fixed.group(1)!);
  return null;
}

/// Port `extract_ram_text` (laptop): kapasitas RAM GB, atau null.
int? mlExtractRamText(String? text) {
  final t = (text ?? '').toLowerCase();
  final mRam = RegExp(r'\bram\s*(\d{1,2})\s*gb\b').firstMatch(t);
  if (mRam != null) return int.parse(mRam.group(1)!);
  final mDdr =
      RegExp(r'(\d{1,2})\s*gb\s*(?:ddr|ram|memory)\b').firstMatch(t);
  if (mDdr != null) return int.parse(mDdr.group(1)!);
  final mSlash = RegExp(r'\b(\d{1,2})\s*/\s*\d{3,4}\b').firstMatch(t);
  if (mSlash != null) return int.parse(mSlash.group(1)!);
  return null;
}

/// Port `extract_chipset`: chipset huruf+3 digit, atau null.
String? mlExtractChipset(String? text) {
  final m = RegExp(r'\b([abxzi]\d{3})[a-z]{0,2}\b')
      .firstMatch((text ?? '').toLowerCase());
  return m?.group(1);
}

// ---------------------------------------------------------------------------
// Perakit fitur per kategori — null bila ML tak tersedia untuk item itu.
// ---------------------------------------------------------------------------

double? _passmarkLn(Benchmark benchmark, String token, String type) {
  final entry = benchmark.passmarkScore(token, type);
  final score = entry?['score'];
  if (score is! num || score <= 0) return null;
  return math.log(score.toDouble());
}

/// gpu: ln_passmark (PassMark G3D) + vram_gb + cond. Model tak cocok
/// -> null (jalur lama). VRAM tak ter-parse -> median kategori JSON
/// (kesenjangan vs median per model Python — lihat header file).
Map<String, double>? mlGpuFeatures(
  Benchmark benchmark,
  String text,
  String? condition,
  MlCategoryModel model,
) {
  final token = mlExtractGpuModel(text);
  if (token == null) return null;
  final ln = _passmarkLn(benchmark, token, 'gpu');
  if (ln == null) return null;
  final vram = benchmark.extractVramGb(text)?.toDouble() ??
      model.defaults['vram_gb'];
  if (vram == null) return null;
  final (cn, cs) = mlConditionDummies(condition, model);
  return {
    'ln_passmark': ln,
    'vram_gb': vram,
    'cond_new': cn,
    'cond_second': cs,
  };
}

/// cpu: ln_passmark (CPU Mark) + cond. Model tak cocok -> null.
Map<String, double>? mlCpuFeatures(
  Benchmark benchmark,
  String text,
  String? condition,
  MlCategoryModel model,
) {
  final token = mlExtractCpuModel(text);
  if (token == null) return null;
  final ln = _passmarkLn(benchmark, token, 'cpu');
  if (ln == null) return null;
  final (cn, cs) = mlConditionDummies(condition, model);
  return {'ln_passmark': ln, 'cond_new': cn, 'cond_second': cs};
}

/// ram: ln_capacity_gb + ddr_gen + is_sodimm + speed_mhz (imputasi median
/// per-DDR dari defaults, fallback median global). Total/DDR hilang -> null.
Map<String, double>? mlRamFeatures(
  String text,
  String? condition,
  MlCategoryModel model,
) {
  final (total, ddr, speed, sodimm) = mlExtractRamCat(text);
  if (total == null || total <= 0 || ddr == null) return null;
  final mhz = speed?.toDouble() ??
      model.defaults['speed_mhz_ddr$ddr'] ??
      model.defaults['speed_mhz'];
  if (mhz == null) return null;
  final (cn, cs) = mlConditionDummies(condition, model);
  return {
    'ln_capacity_gb': math.log(total.toDouble()),
    'ddr_gen': ddr.toDouble(),
    'is_sodimm': sodimm.toDouble(),
    'speed_mhz': mhz,
    'cond_new': cn,
    'cond_second': cs,
  };
}

/// storage: ln_capacity_gb + one-hot tipe + cond. Kapasitas/tipe hilang
/// -> null. (Gerbang JSON menutup pemakaian storage; fitur tetap
/// diimplementasikan seragam.)
Map<String, double>? mlStorageFeatures(
  String text,
  String? condition,
  MlCategoryModel model,
) {
  final (cap, type) = mlExtractStorageCat(text);
  if (cap == null || cap <= 0 || type == null) return null;
  final (cn, cs) = mlConditionDummies(condition, model);
  return {
    'ln_capacity_gb': math.log(cap.toDouble()),
    'type_nvme': type == 'nvme' ? 1.0 : 0.0,
    'type_sata_ssd': type == 'sata_ssd' ? 1.0 : 0.0,
    'type_hdd': type == 'hdd' ? 1.0 : 0.0,
    'cond_new': cn,
    'cond_second': cs,
  };
}

/// motherboard: one-hot chipset_* + cond. Chipset hilang -> null.
/// Chipset di luar daftar JSON -> chipset_other = 1. (Gerbang JSON
/// menutup pemakaian motherboard; fitur tetap diimplementasikan seragam.)
Map<String, double>? mlMotherboardFeatures(
  String text,
  String? condition,
  MlCategoryModel model,
) {
  final chip = mlExtractChipset(text);
  if (chip == null) return null;
  final known = <String>{
    for (final n in model.features.keys)
      if (n.startsWith('chipset_') && n != 'chipset_other') n.substring(8),
  };
  final (cn, cs) = mlConditionDummies(condition, model);
  final out = <String, double>{};
  for (final n in model.features.keys) {
    if (n.startsWith('chipset_')) {
      out[n] = (n == 'chipset_$chip' ||
              (n == 'chipset_other' && !known.contains(chip)))
          ? 1.0
          : 0.0;
    }
  }
  out['cond_new'] = cn;
  out['cond_second'] = cs;
  return out;
}

/// laptop: ln_cpu_passmark + ln_gpu_passmark + has_dgpu + ln_ram_gb +
/// ln_storage_gb + cond. CPU tak cocok, atau RAM/storage hilang -> null.
/// Tanpa dGPU: has_dgpu = 0, ln_gpu_passmark = 0.0 (sesuai Python).
Map<String, double>? mlLaptopFeatures(
  Benchmark benchmark, {
  required String cpuText,
  required String gpuText,
  required String ramText,
  required String storageText,
  int? ramGb,
  int? storageGb,
  required String? condition,
  required MlCategoryModel model,
}) {
  final cpuRes = benchmark.resolveCpuLaptopDetailed(cpuText);
  final cpuEntry = cpuRes.entry;
  final cpuScore = cpuEntry?['score'];
  if (cpuScore is! num || cpuScore <= 0) return null;
  double lnGpu = 0.0;
  var hasDgpu = 0.0;
  if (mlGpuSig(gpuText) != null) {
    final token = mlExtractGpuModel(gpuText);
    if (token == null) return null;
    final ln = _passmarkLn(benchmark, token, 'gpu');
    if (ln == null) return null;
    lnGpu = ln;
    hasDgpu = 1.0;
  }
  var ram = ramGb;
  if (ram == null || ram <= 0) ram = mlExtractRamText(ramText);
  if (ram == null || ram <= 0) return null;
  var sto = storageGb;
  if (sto == null || sto <= 0) sto = mlExtractStorageText(storageText);
  if (sto == null || sto <= 0) return null;
  final (cn, cs) = mlConditionDummies(condition, model);
  return {
    'ln_cpu_passmark': math.log(cpuScore.toDouble()),
    'ln_gpu_passmark': lnGpu,
    'has_dgpu': hasDgpu,
    'ln_ram_gb': math.log(ram.toDouble()),
    'ln_storage_gb': math.log(sto.toDouble()),
    'cond_new': cn,
    'cond_second': cs,
  };
}

/// Ekstraksi + prediksi satu langkah (TANPA gerbang — gerbang diputuskan
/// pemanggil). Null bila kategori tak dikenal atau ekstraksi gagal.
({double price, double low, double high})? mlEstimateFor({
  required MlPriceModels models,
  required String category,
  required Benchmark benchmark,
  required String query,
  String? cpuText,
  String? gpuText,
  int? ramGb,
  int? storageGb,
  required String? condition,
}) {
  final model = models.category(category);
  if (model == null) return null;
  final Map<String, double>? features;
  switch (category) {
    case 'gpu':
      features = mlGpuFeatures(benchmark, query, condition, model);
    case 'cpu':
      features = mlCpuFeatures(benchmark, query, condition, model);
    case 'ram':
      features = mlRamFeatures(query, condition, model);
    case 'storage':
      features = mlStorageFeatures(query, condition, model);
    case 'motherboard':
      features = mlMotherboardFeatures(query, condition, model);
    case 'laptop':
      features = mlLaptopFeatures(
        benchmark,
        cpuText: cpuText ?? query,
        gpuText: gpuText ?? query,
        ramText: query,
        storageText: query,
        ramGb: ramGb,
        storageGb: storageGb,
        condition: condition,
        model: model,
      );
    default:
      return null;
  }
  if (features == null) return null;
  return models.predict(category, features);
}
