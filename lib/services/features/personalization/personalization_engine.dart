// Mesin personalisasi WorthBang — content-based filtering LOKAL.
//
// Fitur AI kedua yang berdiri sendiri (terpisah total dari chatbot
// LLM/Dodo): belajar dari perilaku user di aplikasi, lalu mengurutkan
// produk katalog bundel berdasarkan skor kecocokan. Tanpa server,
// tanpa API luar, deterministik — profil & skor dihitung murni di Dart.
//
// Rumus skor produk (0..1):
//   total = 0.35*kategori + 0.25*platform + 0.25*harga + 0.15*worth
// Bobot event meluruh eksponensial (half-life 14 hari) agar profil
// mengikuti selera terbaru user.
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/local_catalog.dart';

/// Jenis event perilaku user yang dicatat sebagai sinyal preferensi.
enum UserEventType { viewDetail, worthCheck, search, addToDream }

extension UserEventTypeWeight on UserEventType {
  /// Bobot sinyal tiap aksi: niat terkuat = masuk Rakitan Impian.
  double get weight => switch (this) {
        UserEventType.addToDream => 5,
        UserEventType.worthCheck => 3,
        UserEventType.search => 2,
        UserEventType.viewDetail => 1,
      };
}

/// Satu event perilaku. [category] memakai kunci seksi katalog
/// ('gpu', 'cpu', 'motherboard', 'ram', 'storage', 'laptop', 'pc').
class UserEvent {
  const UserEvent({
    required this.type,
    required this.at,
    this.category,
    this.productName,
    this.price,
    this.query,
  });

  final UserEventType type;
  final String? category;
  final String? productName;
  final int? price;
  final String? query;
  final DateTime at;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'category': category,
        'productName': productName,
        'price': price,
        'query': query,
        'at': at.toIso8601String(),
      };

  factory UserEvent.fromJson(Map<String, dynamic> j) => UserEvent(
        type: UserEventType.values.byName(j['type'] as String),
        category: j['category'] as String?,
        productName: j['productName'] as String?,
        price: (j['price'] as num?)?.toInt(),
        query: j['query'] as String?,
        at: DateTime.parse(j['at'] as String),
      );
}

/// Jawaban onboarding: modal awal profil sebelum ada perilaku.
/// [need]: 'gaming'|'editing'|'kerja'; [platform]: 'amd'|'intel'|'bebas'.
class OnboardingProfile {
  const OnboardingProfile({
    required this.need,
    required this.budgetMin,
    required this.budgetMax,
    required this.platform,
  });

  final String need;
  final int budgetMin;
  final int budgetMax;
  final String platform;

  Map<String, dynamic> toJson() => {
        'need': need,
        'budgetMin': budgetMin,
        'budgetMax': budgetMax,
        'platform': platform,
      };

  factory OnboardingProfile.fromJson(Map<String, dynamic> j) =>
      OnboardingProfile(
        need: j['need'] as String,
        budgetMin: (j['budgetMin'] as num).toInt(),
        budgetMax: (j['budgetMax'] as num).toInt(),
        platform: j['platform'] as String,
      );
}

/// Profil preferensi hasil agregasi event berbobot + prior onboarding.
/// [categoryWeights]/[platformWeights] = massa bobot SETELAH decay
/// (belum dinormalisasi); [categoryShares]/[platformShares] = bagiannya
/// (0..1, jumlah 1 bila ada sinyal). [budgetCenter] = pusat budget.
class PreferenceProfile {
  const PreferenceProfile({
    required this.categoryWeights,
    required this.categoryShares,
    required this.platformWeights,
    required this.platformShares,
    required this.budgetCenter,
    required this.hasEvents,
    required this.hasOnboarding,
  });

  final Map<String, double> categoryWeights;
  final Map<String, double> categoryShares;
  final Map<String, double> platformWeights;
  final Map<String, double> platformShares;
  final int? budgetCenter;
  final bool hasEvents;
  final bool hasOnboarding;

  bool get isColdStart => !hasEvents && !hasOnboarding;
}

/// Produk + skor kecocokannya. [reason] = label alasan singkat yang
/// aman ditampilkan ke user (null bila tidak ada sinyal kuat).
class ScoredProduct {
  const ScoredProduct({required this.item, required this.score, this.reason});

  final CatalogItem item;
  final double score;
  final String? reason;
}

/// Deteksi platform/vendor dari nama produk (token spec):
/// ryzen/radeon/amd -> 'amd', intel/core -> 'intel',
/// nvidia/geforce/rtx/gtx -> 'nvidia'. Null bila tak terdeteksi.
String? detectPlatform(String model) {
  final s = model.toLowerCase();
  bool has(String t) => s.contains(t);
  if (has('nvidia') || has('geforce') || has('rtx') || has('gtx')) {
    return 'nvidia';
  }
  if (has('ryzen') || has('radeon') || has('amd')) return 'amd';
  if (has('intel') || has('core')) return 'intel';
  return null;
}

/// Deteksi kategori dari nama produk. CatalogItem katalog bundel hanya
/// membawa nama + harga (seksi asalnya hilang saat daftar diratakan),
/// jadi kategori ditebak dari token nama — heuristik v1, sengaja
/// konservatif: urutan cek motherboard -> ram -> storage -> gpu -> cpu.
String? detectCategory(String model) {
  final s = model.toLowerCase();
  if (s.contains('motherboard') || s.contains('mainboard')) {
    return 'motherboard';
  }
  if (RegExp(r'\bddr[345]\b').hasMatch(s) || s.contains('sodimm')) {
    return 'ram';
  }
  if (s.contains('ssd') || s.contains('nvme') || s.contains('hdd')) {
    return 'storage';
  }
  if (s.contains('rtx') ||
      s.contains('gtx') ||
      s.contains('geforce') ||
      s.contains('radeon') ||
      s.contains('vga')) {
    return 'gpu';
  }
  if (s.contains('ryzen') ||
      s.contains('athlon') ||
      s.contains('threadripper') ||
      s.contains('xeon') ||
      s.contains('pentium') ||
      RegExp(r'core i[3579]').hasMatch(s)) {
    return 'cpu';
  }
  if (s.contains('laptop') || s.contains('notebook')) return 'laptop';
  return null;
}

const _categoryLabels = {
  'gpu': 'GPU',
  'cpu': 'CPU',
  'motherboard': 'Motherboard',
  'ram': 'RAM',
  'storage': 'Storage',
  'laptop': 'Laptop',
  'pc': 'PC Rakitan',
};

/// Prior kategori dari kebutuhan onboarding (heuristik v1, jumlah 1.0).
/// Dipakai sebagai massa sintetis berbobot 10 yang ikut meluruh.
const _needCategoryPrior = {
  'gaming': {'gpu': .45, 'cpu': .20, 'storage': .15, 'ram': .10, 'motherboard': .10},
  'editing': {'cpu': .30, 'gpu': .30, 'ram': .15, 'storage': .15, 'motherboard': .10},
  'kerja': {'cpu': .25, 'storage': .25, 'ram': .20, 'motherboard': .20, 'gpu': .10},
};

double _decay(DateTime at, DateTime now) {
  final ageDays = now.difference(at).inSeconds / 86400.0;
  if (ageDays <= 0) return 1;
  return pow(0.5, ageDays / 14).toDouble();
}

Map<String, double> _shares(Map<String, double> weights) {
  final total = weights.values.fold(0.0, (a, b) => a + b);
  if (total <= 0) return const {};
  return {for (final e in weights.entries) e.key: e.value / total};
}

int _median(List<int> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return ((sorted[mid - 1] + sorted[mid]) / 2).round();
}

/// Engine personalisasi. Menerima [SharedPreferences] yang sudah
/// dimuat (agar mudah dites) dan peta skor worth opsional
/// [worthByNameKey] (key = nama produk lowercase, nilai 0..1).
class PersonalizationEngine {
  PersonalizationEngine(this._prefs, {Map<String, double>? worthByNameKey})
      : _worthByNameKey = worthByNameKey ?? const {} {
    _events = _loadEvents();
    _loadOnboarding();
  }

  static const eventsKey = 'wb_events_v1';
  static const onboardingKey = 'wb_onboarding_v1';
  static const maxEvents = 500;

  /// Notifier pembaruan profil preferensi agar UI yang sedang aktif
  /// (mis. etalase Cari Produk) dapat langsung memuat ulang data.
  static final ValueNotifier<int> onboardingVersion = ValueNotifier<int>(0);

  /// Bobot massa prior onboarding (setara 10 event viewDetail segar).
  static const onboardingPriorWeight = 10.0;

  final SharedPreferences _prefs;
  final Map<String, double> _worthByNameKey;
  late List<UserEvent> _events;
  OnboardingProfile? _onboarding;
  DateTime? _onboardingAt;

  List<UserEvent> _loadEvents() {
    try {
      final raw = _prefs.getString(eventsKey);
      if (raw == null) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return [
        for (final e in list)
          UserEvent.fromJson(e as Map<String, dynamic>),
      ];
    } catch (_) {
      return [];
    }
  }

  void _loadOnboarding() {
    try {
      final raw = _prefs.getString(onboardingKey);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _onboarding = OnboardingProfile.fromJson(j);
      final at = j['savedAt'] as String?;
      _onboardingAt = at == null ? null : DateTime.tryParse(at);
    } catch (_) {
      _onboarding = null;
    }
  }

  /// Catat satu event perilaku; daftar dibatasi [maxEvents] (FIFO:
  /// yang paling lama dibuang duluan).
  Future<void> record(UserEvent e) async {
    _events = [..._events, e];
    if (_events.length > maxEvents) {
      _events = _events.sublist(_events.length - maxEvents);
    }
    await _prefs.setString(
      eventsKey,
      jsonEncode([for (final ev in _events) ev.toJson()]),
    );
  }

  Future<void> saveOnboarding(OnboardingProfile p) async {
    _onboarding = p;
    _onboardingAt = DateTime.now();
    await _prefs.setString(
      onboardingKey,
      jsonEncode({...p.toJson(), 'savedAt': _onboardingAt!.toIso8601String()}),
    );
    onboardingVersion.value++;
  }

  Future<bool> hasOnboarding() async => _onboarding != null;

  Future<OnboardingProfile?> onboarding() async => _onboarding;

  /// Bangun profil preferensi per [now] (default: sekarang).
  PreferenceProfile profile({DateTime? now}) {
    final t = now ?? DateTime.now();
    final catW = <String, double>{};
    final platW = <String, double>{};
    final prices = <int>[];

    for (final e in _events) {
      final w = e.type.weight * _decay(e.at, t);
      final cat = e.category;
      if (cat != null) catW[cat] = (catW[cat] ?? 0) + w;
      final name = e.productName;
      if (name != null) {
        final p = detectPlatform(name);
        if (p != null) platW[p] = (platW[p] ?? 0) + w;
      }
      final price = e.price;
      if (price != null && price > 0) prices.add(price);
    }

    final ob = _onboarding;
    if (ob != null) {
      final at = _onboardingAt;
      final pw = onboardingPriorWeight * (at == null ? 1 : _decay(at, t));
      final prior = _needCategoryPrior[ob.need];
      if (prior != null) {
        for (final e in prior.entries) {
          catW[e.key] = (catW[e.key] ?? 0) + pw * e.value;
        }
      }
      if (ob.platform == 'amd' || ob.platform == 'intel') {
        platW[ob.platform] = (platW[ob.platform] ?? 0) + pw;
      }
    }

    return PreferenceProfile(
      categoryWeights: catW,
      categoryShares: _shares(catW),
      platformWeights: platW,
      platformShares: _shares(platW),
      budgetCenter: prices.isNotEmpty
          ? _median(prices)
          : (ob == null ? null : ((ob.budgetMin + ob.budgetMax) / 2).round()),
      hasEvents: _events.isNotEmpty,
      hasOnboarding: ob != null,
    );
  }

  /// Skor worth fallback dari daftar yang sedang di-rank: rasio harga
  /// item terhadap median kategorinya — makin murah dari median makin
  /// worth. worth = clamp(0.5 * median / price, 0..1); harga == median
  /// -> 0.5, setengah median -> 1.0, dua kali median -> 0.25.
  Map<String, double> _fallbackWorth(List<CatalogItem> items) {
    final byCat = <String, List<int>>{};
    for (final it in items) {
      final cat = detectCategory(it.model);
      if (cat != null && it.price > 0) {
        byCat.putIfAbsent(cat, () => []).add(it.price);
      }
    }
    final medians = {
      for (final e in byCat.entries) e.key: _median(e.value),
    };
    return {
      for (final it in items)
        it.model: () {
          final cat = detectCategory(it.model);
          final med = cat == null ? null : medians[cat];
          if (med == null || it.price <= 0) return 0.5;
          return (0.5 * med / it.price).clamp(0.0, 1.0);
        }(),
    };
  }

  double _worthOf(CatalogItem item, Map<String, double> fallback) {
    final injected = _worthByNameKey[item.model.toLowerCase()];
    if (injected != null) return injected.clamp(0.0, 1.0);
    return fallback[item.model] ?? 0.5;
  }

  /// Urutkan [items] berdasarkan skor kecocokan (tertinggi dulu).
  /// Seri skor dipecah berdasarkan nama model agar deterministik.
  List<ScoredProduct> rank(List<CatalogItem> items, {DateTime? now}) {
    final prof = profile(now: now);
    final fallback = _fallbackWorth(items);
    final center = prof.budgetCenter;

    ScoredProduct score(CatalogItem item) {
      final cat = detectCategory(item.model);
      // Tanpa sinyal kategori sama sekali, shares kosong -> 0 untuk
      // semua; penentunya berpindah ke worth (sesuai desain).
      final catScore = cat == null ? 0.0 : (prof.categoryShares[cat] ?? 0);
      final plat = detectPlatform(item.model);
      final platScore = plat == null || prof.platformShares.isEmpty
          ? 0.5
          : (prof.platformShares[plat] ?? 0);
      final priceScore = center == null || item.price <= 0
          ? 0.5
          : 1 / (1 + (log(item.price / center)).abs());
      final worthScore = _worthOf(item, fallback);
      final total = 0.35 * catScore +
          0.25 * platScore +
          0.25 * priceScore +
          0.15 * worthScore;
      return ScoredProduct(
        item: item,
        score: total,
        reason: cat != null && catScore >= 0.3
            ? 'Sering kamu lihat: ${_categoryLabels[cat] ?? cat}'
            : null,
      );
    }

    final scored = [for (final it in items) score(it)];
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.item.model.compareTo(b.item.model);
    });
    return scored;
  }

  /// Etalase menu cari: [limit] produk pilihan personalisasi.
  /// Ambil 2x [limit] skor teratas lalu acak terbobot (peluang
  /// proporsional skor + 0.1) memakai [rng]. Cold start total (tanpa
  /// event & onboarding): murni urutan worth menurun, tanpa acak.
  List<CatalogItem> showcase(
    List<CatalogItem> items, {
    int limit = 20,
    Random? rng,
    DateTime? now,
  }) {
    if (profile(now: now).isColdStart) {
      final fallback = _fallbackWorth(items);
      final byWorth = [...items]..sort((a, b) {
          final byW = _worthOf(b, fallback).compareTo(_worthOf(a, fallback));
          return byW != 0 ? byW : a.model.compareTo(b.model);
        });
      return byWorth.take(limit).toList();
    }
    final pool = rank(items, now: now).take(limit * 2).toList();
    final random = rng ?? Random();
    final picked = <CatalogItem>[];
    while (picked.length < limit && pool.isNotEmpty) {
      var totalW = 0.0;
      for (final sp in pool) {
        totalW += sp.score + 0.1;
      }
      var roll = random.nextDouble() * totalW;
      var idx = 0;
      for (var i = 0; i < pool.length; i++) {
        roll -= pool[i].score + 0.1;
        if (roll <= 0) {
          idx = i;
          break;
        }
      }
      picked.add(pool.removeAt(idx).item);
    }
    return picked;
  }
}
