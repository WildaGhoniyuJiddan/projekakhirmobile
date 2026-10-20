/// Port setia services/relevance.py (repo lama): deteksi laptop/build/
/// aksesori + relevansi listing komponen PC.
///
/// Catatan regex: pola ditranskrip persis dari Python. Semantik \b dan
/// \d di Dart berbasis ASCII (Python: Unicode) — untuk judul marketplace
/// Indonesia yang praktis ASCII, hasilnya setara.
library;

const List<String> buildWords = [
  'pc gaming',
  'gaming pc',
  'pc rakitan',
  'rakit pc',
  'rakitan pc',
  'komputer',
  'desktop',
  'pc mini',
  'mini itx',
  'built up',
  'full set pc',
  'pc full set',
  'paket pc',
  'paket gaming',
  'cpu rakitan',
  'pc build',
  'build pc',
  'hackintosh',
];

const List<String> accessoryWords = [
  'fan ',
  'kipas',
  'cooler ',
  'heatsink',
  'radiator',
  'dus ',
  'box only',
  'bracket',
  'cable',
  'kabel',
  'fleksibel',
  'flexible',
  'riser',
  'backplate',
  'sticker',
  'case ',
  'casing',
  'housing',
  'adapter',
  'adaptor',
  'cover ',
  'enclosure',
  'charger',
  'baterai',
  'battery',
  'battrey',
  'batre',
  'keyboard',
  'mouse ',
  'headset',
  'tempered glass',
  'hydrogel',
  'skin ',
  'sleeve',
  'tas ',
  'bag ',
  'lcd ',
  'led lcd',
  'panel lcd',
  'engsel',
  'hinge',
  'touchpad',
  'speaker laptop',
  'sparepart',
  'spare part',
];

// ---------------------------------------------------------------------------
// Taksonomi & Deteksi Laptop Komprehensif
// ---------------------------------------------------------------------------

final RegExp _laptopGenericWords = RegExp(
  r'\b(?:laptop|notebook|netbook|macbook|ultrabook|chromebook|2-in-1|two-in-one)\b',
  caseSensitive: false,
);

// Seri yang secara eksklusif merupakan unit laptop (bukan komponen GPU/CPU/mobo)
final RegExp _exclusiveLaptopSeries = RegExp(
  r'\b(?:'
  // Dell & Alienware
  r'alienware|aurora\s*(?:1[5678]|\d{2})|dell\s*g1[56]|dell\s*g[357]|xps\s*1[34567]|'
  r'inspiron(?:\s*1[3456])?|latitude(?:\s*\d{4})?|vostro(?:\s*\d{4})?|precision(?:\s*\d{4})?|'
  // Lenovo
  r'legion(?:\s*(?:pro|slim)?\s*\d{1,2}[a-z]*)?|loq(?:\s*\d{1,2}[a-z]*)?|'
  r'ideapad(?:\s*(?:slim|flex|gaming|pro)?\s*\d{1,2}[a-z]*)?|'
  r'yoga(?:\s*(?:slim|pro|book)?\s*\d{1,2}[a-z]*)?|thinkpad(?:\s*[a-z]\d{2,4}[a-z]*)?|thinkbook|'
  // Acer
  r'acer\s*nitro(?:\s*v)?(?:\s*\d{1,2}[a-z]*)?|nitro\s*(?:v\s*\d{1,2}|[57]\b)|swift(?:\s*(?:go|edge|x|\d{1,2}))?|'
  r'aspire(?:\s*(?:lite|vero|pro|\d{1,2}))?|travelmate|spin\s*\d|'
  // HP
  r'victus(?:\s*\d{1,2})?|omen(?:\s*(?:transcend|\d{1,2}))?|'
  r'pavilion(?:\s*(?:plus|aero|gaming|x360|\d{1,2}))?|'
  r'elitebook(?:\s*\d{3,4})?|probook(?:\s*\d{3,4})?|zbook|dragonfly|'
  r'hp\s*1[45]s\b|hp\s*24[05]\b|envy(?:\s*x360|\s*\d{1,2})?|spectre(?:\s*x360|\s*\d{1,2})?|'
  // MSI
  r'katana(?:\s*\d{2})?|cyborg(?:\s*\d{2})?|msi\s*sword|sword\s*1[567]|'
  r'msi\s*crosshair|crosshair\s*1[567]|msi\s*pulse|pulse\s*1[567]|'
  r'gf6[35]\b|thin\s*15\b|bravo\s*15\b|modern\s*1[45]\b|prestige\s*\d{2}\b|'
  r'summit\s*e?\d{2}\b|stealth\s*\d{2}\b|vector\s*g[pe]\b|raider\s*ge\b|titan\s*gt\b|'
  // Apple
  r'macbook(?:\s*(?:air|pro))?|'
  // Brand Lokal Indonesia
  r'pongo(?:\s*\d{3})?|hype\s*\d{1,2}\b|'
  r'workplus|workpro|pixelwar|360\s*stylus|soulmate|'
  // Brand Ekosistem & Impor / Ex-Corporate
  r"matebook|inbook|gt\s*book|redmibook|realme\s*book|"
  r"surface\s*(?:pro|laptop|go|book)|lifebook|let'?s\s*note|toughbook|"
  r'dynabook|portege|tecra|vaio(?:\s*[a-z]{2}\d{2})?|'
  // ASUS
  r'zenbook(?:\s*(?:flip|duo|pro|s))?|vivobook(?:\s*(?:go|pro|s|flip|slate))?|expertbook|'
  r'zephyrus(?:\s*g\d{2})?|rog\s*flow|rog\s*ally|'
  // Others
  r'razer\s*blade|colorful\s*evol'
  r')\b',
  caseSensitive: false,
);

// Brand gaming dual-use yang membedakan kartu grafis vs model laptop spesifik
final RegExp _dualUseLaptopSpecific = RegExp(
  r'\b(?:'
  r'tuf\s*(?:gaming\s*)?(?:a1[4567]|f1[567]|dash\s*f1[567]|[af]\d{2,3})|'
  r'fa\d{3}[a-z]*|fx\d{3}[a-z]*|'
  r'rog\s*strix\s*(?:g1[5-8]|scar|hero|\d{2})|'
  r'predator\s*(?:helios|triton)|helios\s*(?:neo|\d{2})|triton\s*\d{2}|'
  r'aorus\s*(?:1[567]|master\s*1[567])'
  r')\b',
  caseSensitive: false,
);

// Indikator fisik layar / display (laptop selalu memiliki layar fisik)
final RegExp _screenSizeRe = RegExp(
  '\b1[1-7](?:\\.[0-9])?\\s*(?:["”]|inch|-inch|\\s*inci)\b',
  caseSensitive: false,
);

final RegExp _screenFeatureRe = RegExp(
  r'\b(?:fhd|qhd|wqhd|2\.8k|2\.5k|3k|4k|oled|ips)\b.*\b(?:120hz|144hz|165hz|240hz|300hz|360hz|touch(?:screen)?)\b|'
  r'\b(?:120hz|144hz|165hz|240hz|300hz|360hz)\b.*\b(?:fhd|qhd|wqhd|2\.8k|2\.5k|3k|4k|oled|ips)\b',
  caseSensitive: false,
);

// Prosesor mobile (laptop) dengan suffix H/HX/HS/HK/U atau seri mobile 3-5 digit
final RegExp mobileCpuRe = RegExp(
  r'\b(?:'
  r'(?:core\s*(?:ultra\s*)?[3579]|ultra\s*[579]|intel\s*core|i[3579])\s*[- ]?\s*(?:\d{3,5}\s*(?:hx|hs|hk|h|u))\b|'
  r'ryzen\s*(?:ai)?\s*[3579]\s*[- ]?\s*(?:\d{4}[a-z]{0,2}\s*(?:hs|hx|h|u)|\d{3}\b)|'
  r'core\s+ultra|ryzen\s+ai'
  r')',
  caseSensitive: false,
);

// Penanda spesifikasi sistem lengkap gabungan (RAM + Storage) khas laptop/prebuilt
final RegExp systemSpecRe = RegExp(
  r'\b\d{1,2}\s*gb\s*/\s*\d{1,2}\s*(?:gb)?\s*/\s*\d{3,4}\s*gb\b|'
  r'\b\d{1,2}\s*(?:gb)?\s*/\s*\d{3,4}\s*(?:gb|tb)\b|'
  r'\b(?:8|16|32|64)\s*gb\s+(?:256\s*gb|512\s*gb|1\s*tb|2\s*tb)\b',
  caseSensitive: false,
);

// Penanda OS / software terpasang pada unit lengkap
final RegExp bundledOsRe = RegExp(
  r'\b(?:w11|win\s*11|windows\s*11|w10|win\s*10|windows\s*10|ohs\d*|office\s*home)\b',
  caseSensitive: false,
);

final RegExp _buildWordsRe = RegExp(
  r'\b(?:'
  r'pc\s*gaming|gaming\s*pc|pc\s*rakitan|rakit\s*pc|rakitan\s*pc|'
  r'pc\s*build|build\s*pc|komputer|desktop\s*pc|pc\s*mini|mini\s*itx|'
  r'built\s*up|full\s*set\s*pc|pc\s*full\s*set|paket\s*full\s*set|paket\s*pc|paket\s*gaming|cpu\s*rakitan|'
  r'hackintosh'
  r')\b',
  caseSensitive: false,
);

// Penanda komponen aktif
final RegExp gpuMarkerRe = RegExp(
  r'\b(?:rtx|gtx)\s*\d{3,4}\b|\brx\s*\d{3,4}\b|\bvga\b|\bradeon\s*rx\b|\bgeforce\b|\barc\s*a?\d*',
  caseSensitive: false,
);

final RegExp cpuMarkerRe = RegExp(
  r'\b(?:'
  r'core\s*(?:ultra\s*)?[3579]|ultra\s*[579]|intel\s*core|i[3579]|'
  r'ryzen\s*(?:ai\s*)?[3579]'
  r')\s*[- ]?\s*\d{3,5}[a-z]{0,3}\b',
  caseSensitive: false,
);

/// Deteksi apakah judul/spek merupakan unit laptop utuh.
bool isLaptopListing(String title, [String specText = '']) {
  final text = '$title $specText'.toLowerCase();
  if (accessoryWords.any((word) => text.contains(word))) return false;
  // Brand kartu grafis lepas yang tidak pernah memproduksi laptop
  if (text.contains('sapphire')) return false;
  if (_laptopGenericWords.hasMatch(text)) return true;
  if (_exclusiveLaptopSeries.hasMatch(text)) return true;
  if (_dualUseLaptopSpecific.hasMatch(text)) return true;
  if (_screenSizeRe.hasMatch(text)) return true;
  if (_screenFeatureRe.hasMatch(text)) return true;
  if (mobileCpuRe.hasMatch(text) &&
      (systemSpecRe.hasMatch(text) || bundledOsRe.hasMatch(text))) {
    return true;
  }
  return false;
}

/// Deteksi apakah judul merupakan paket rakitan PC / sistem desktop utuh.
bool isPcBuildListing(String? title) {
  final text = (title ?? '').toLowerCase();
  return _buildWordsRe.hasMatch(text);
}

/// Tentukan tipe komponen dari query pencarian.
String? componentTypeFromQuery(String? query) {
  final text = (query ?? '').toLowerCase();
  if (isLaptopListing(text)) return 'laptop';
  if (RegExp(r'\b(?:rtx|gtx|rx|arc)\s*(?:[ab]?\d{3,4})').hasMatch(text)) {
    return 'gpu';
  }
  if (RegExp(r'\b(?:ryzen\s*(?:ai\s*)?[3579]|core\s*(?:ultra\s*)?[3579]|ultra\s*[579]|intel\s*core|i[3579])\s*[- ]?\d{3,5}')
      .hasMatch(text)) {
    return 'cpu';
  }
  // Section pasif: RAM (ddr + kapasitas), storage, motherboard.
  if (RegExp(r'\bram\b|\bmemori\b|\bmemory\b|\bddr[345]\b').hasMatch(text)) {
    return 'ram';
  }
  if (RegExp(r'\bssd\b|\bhdd\b|\bnvme\b|\bharddisk\b|\bhardisk\b|\bm\.?2\s*(?:sata|nvme)\b')
      .hasMatch(text)) {
    return 'storage';
  }
  if (RegExp(r'\bmotherboard\b|\bmobo\b').hasMatch(text) ||
      RegExp(r'\b[a-z]\d{3,4}\w*-?m?\b').hasMatch(text)) {
    return 'motherboard';
  }
  return null;
}

bool isStandaloneComponentQuery(String? query) {
  final text = (query ?? '').toLowerCase();
  final t = componentTypeFromQuery(text);
  return t != null && t != 'laptop' && !isLaptopListing(text);
}

(String, String)? _componentSignature(String? value, String? componentType) {
  final text = (value ?? '').toLowerCase();
  if (componentType == 'gpu') {
    // Suffix Ti/Super/XT = produk BEDA ("RTX 4060" != "RTX 4060 Ti")
    final match =
        RegExp(r'\b(rtx|gtx|rx|arc)\s*([ab]?\d{3,4})\s*(ti|super|xt)?\b')
            .firstMatch(text);
    if (match != null) {
      return ('gpu', '${match.group(1)}${match.group(2)}${match.group(3) ?? ''}');
    }
  }
  if (componentType == 'cpu') {
    // Suffix huruf (X/F/K/H) = SKU beda ("5600" != "5600X")
    final match =
        RegExp(r'\b(ryzen\s*[3579]|core\s*i[3579])\s*-?\s*(\d{4,5})([a-z]{0,2})?\b')
            .firstMatch(text);
    if (match != null) {
      final fam = match.group(1)!.replaceAll(RegExp(r'\s+'), '');
      return ('cpu', '$fam${match.group(2)}${match.group(3) ?? ''}');
    }
  }
  if (componentType == 'ram') {
    final ddr = RegExp(r'ddr\s*([345])').firstMatch(text);
    final gb = RegExp(r'(\d{1,2})\s*gb\b').firstMatch(text);
    if (ddr != null && gb != null) {
      return ('ram', 'ddr${ddr.group(1)} ${gb.group(1)}gb');
    }
  }
  if (componentType == 'storage') {
    final String? kind = RegExp(r'\b(ssd|nvme|m\.?2)\b').hasMatch(text)
        ? 'ssd'
        : (RegExp(r'\bhdd\b|\bharddisk\b|\bhardisk\b').hasMatch(text)
            ? 'hdd'
            : null);
    if (kind != null) {
      final gb = RegExp(r'(\d{1,3})\s*gb\b').firstMatch(text);
      final tb = RegExp(r'(\d)\s*tb\b').firstMatch(text);
      final size =
          gb != null ? '${gb.group(1)}gb' : (tb != null ? '${tb.group(1)}tb' : null);
      if (size != null) return ('storage', '$kind $size');
    }
  }
  if (componentType == 'motherboard') {
    final chipset = RegExp(r'\b([abxzi]\d{3})[a-z]{0,2}\b').firstMatch(text);
    if (chipset != null) return ('motherboard', chipset.group(1)!);
  }
  return null;
}

/// Tolak listing yang tidak relevan dengan query komponen satuan.
bool isRelevantPcListing(String? query, String? title, [String? componentType]) {
  final queryText = (query ?? '').toLowerCase();
  final titleText = (title ?? '').toLowerCase();
  final resolvedType = componentType ?? componentTypeFromQuery(queryText);

  final querySignature = _componentSignature(queryText, resolvedType);
  final titleSignature = _componentSignature(titleText, resolvedType);
  if (querySignature != null &&
      titleSignature != null &&
      querySignature != titleSignature) {
    return false;
  }

  // Aksesori & spare part selalu gugur
  if (accessoryWords.any((word) => titleText.contains(word))) return false;

  // Mode LAPTOP
  if (resolvedType == 'laptop') {
    return isLaptopListing(titleText);
  }

  // Mode KOMPONEN PC SATUAN (GPU, CPU, RAM, Storage, Mobo)
  // 1. Hard-gate: unit laptop TIDAK BOLEH menjadi pembanding komponen PC
  if (isLaptopListing(titleText)) return false;

  // 2. Hard-gate: sistem PC rakitan lengkap TIDAK BOLEH jadi pembanding
  if (isPcBuildListing(titleText)) return false;

  if (titleText.contains('bundle') ||
      titleText.contains('bundling') ||
      titleText.contains('paket')) {
    return false;
  }

  // Filter khusus GPU lepas
  if (resolvedType == 'gpu') {
    // Konflik kapasitas VRAM jika query eksplisit menyebutkan VRAM
    final queryVram = RegExp(r'\b(\d{1,2})\s*gb\b').firstMatch(queryText);
    final titleVram = RegExp(r'\b(\d{1,2})\s*gb\b').firstMatch(titleText);
    if (queryVram != null &&
        titleVram != null &&
        queryVram.group(1) != titleVram.group(1)) {
      return false;
    }

    // Kartu grafis lepas tidak pernah mencantumkan prosesor CPU
    if (cpuMarkerRe.hasMatch(titleText)) return false;
    // Kartu grafis lepas tidak memiliki ukuran layar fisik
    if (_screenSizeRe.hasMatch(titleText) ||
        _screenFeatureRe.hasMatch(titleText)) {
      return false;
    }
    // Kartu grafis lepas tidak memiliki notasi spec memori/storage ganda
    if (systemSpecRe.hasMatch(titleText)) return false;
    // Kartu grafis lepas tidak dilengkapi sistem operasi terpasang
    if (bundledOsRe.hasMatch(titleText)) return false;
    // Multi-chipset GPU dalam 1 judul (mis. "RTX5060 / RTX5050") gugur
    final matches =
        RegExp(r'\b(?:rtx|gtx|rx|arc)\s*([ab]?\d{3,4})\s*(ti|super|xt)?\b')
            .allMatches(titleText)
            .toList();
    if (matches.isNotEmpty) {
      final distinctModels = <String>{
        for (final m in matches) '${m.group(1)}${m.group(2) ?? ''}',
      };
      if (distinctModels.length > 1) return false;
    }
  }

  // Filter khusus CPU lepas
  if (resolvedType == 'cpu') {
    // Prosesor desktop satuan tidak pernah mencantumkan GPU diskret
    if (gpuMarkerRe.hasMatch(titleText)) return false;
    // Prosesor desktop satuan tidak menggunakan suffix mobile laptop
    if (mobileCpuRe.hasMatch(titleText)) return false;
    if (_screenSizeRe.hasMatch(titleText) ||
        _screenFeatureRe.hasMatch(titleText)) {
      return false;
    }
    if (systemSpecRe.hasMatch(titleText) || bundledOsRe.hasMatch(titleText)) {
      return false;
    }
  }

  // Filter khusus komponen pasif (RAM, Storage, Motherboard)
  if (resolvedType == 'ram' ||
      resolvedType == 'storage' ||
      resolvedType == 'motherboard') {
    if (gpuMarkerRe.hasMatch(titleText) || cpuMarkerRe.hasMatch(titleText)) {
      return false;
    }
    if (RegExp(r'\s[+|]\s').hasMatch(titleText)) return false;
    if (_screenSizeRe.hasMatch(titleText) || bundledOsRe.hasMatch(titleText)) {
      return false;
    }
    if (resolvedType == 'ram' &&
        RegExp(r'ram\s*\d+\s*gb\b.*\b(?:ssd|nvme|win|fhd|intel|core)\b|\b(?:ssd\d|ssd)\s*\d+\s*[gt]b\b')
            .hasMatch(titleText)) {
      return false;
    }
  }

  return true;
}

/// Build safe marketplace queries without changing the canonical model.
List<String> queryVariants(String? query, [int maxVariants = 5]) {
  final base = (query ?? '')
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .join(' ')
      .trim();
  if (base.isEmpty) return [];
  final componentType = componentTypeFromQuery(base);
  final List<String> variants;
  if (componentType == 'gpu') {
    final brandVariant =
        base.toLowerCase().startsWith('rx ') ? 'Radeon $base' : 'graphics card $base';
    variants = [
      base,
      'VGA $base',
      brandVariant,
      '$base bekas',
      '$base baru',
      'graphics card $base',
    ];
  } else if (componentType == 'cpu') {
    variants = [base, 'processor $base', '$base bekas', '$base baru', 'CPU $base'];
  } else {
    variants = [base, '$base bekas', '$base baru'];
  }
  final seen = <String>{};
  final result = <String>[];
  for (final variant in variants) {
    final normalized =
        variant.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).join(' ');
    final key = normalized.toLowerCase();
    if (!seen.contains(key)) {
      seen.add(key);
      result.add(normalized);
    }
  }
  final cap = maxVariants < 1 ? 1 : maxVariants;
  return result.length <= cap ? result : result.sublist(0, cap);
}
