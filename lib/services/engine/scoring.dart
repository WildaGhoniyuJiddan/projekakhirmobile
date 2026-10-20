import 'dart:math' as math;

/// Port setia services/scoring.py (repo lama).

/// Pembulatan ala Python `round()` — half-to-even (banker's rounding),
/// BUKAN half-away-from-zero seperti `double.round()` di Dart.
int pyRoundInt(double value) {
  final f = value.floor();
  final diff = value - f;
  if (diff < 0.5) return f;
  if (diff > 0.5) return f + 1;
  // Tepat di tengah -> pilih yang genap.
  return f.isEven ? f : f + 1;
}

/// Python `round(value, digits)` (half-to-even, pendekatan skala 10^n).
double pyRound(double value, int digits) {
  var scale = 1.0;
  for (var i = 0; i < digits; i++) {
    scale *= 10;
  }
  return pyRoundInt(value * scale) / scale;
}

/// statistics.median() Python untuk daftar angka.
double medianOf(List<num> values) {
  final sorted = List<num>.of(values)..sort();
  final n = sorted.length;
  final mid = n ~/ 2;
  if (n % 2 == 1) return sorted[mid].toDouble();
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Sort STABIL ala Python (sorted/list.sort mempertahankan urutan asal
/// untuk kunci yang seri). `List.sort` Dart TIDAK stabil, jadi seri
/// dipecahkan dengan indeks asal.
void stableSort<T>(List<T> list, int Function(T a, T b) compare) {
  final decorated = <(int, T)>[
    for (var i = 0; i < list.length; i++) (i, list[i]),
  ];
  decorated.sort((a, b) {
    final c = compare(a.$2, b.$2);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  for (var i = 0; i < list.length; i++) {
    list[i] = decorated[i].$2;
  }
}

double _clamp(double value, [double low = 0, double high = 100]) =>
    math.max(low, math.min(high, value));

/// Mirror dataclass ScoreResult Python.
class ScoreResult {
  const ScoreResult({
    required this.score,
    required this.verdict,
    required this.recommendation,
    required this.referencePrice,
    required this.deltaPercent,
    this.fairPriceLow = 0,
    this.fairPriceHigh = 0,
    this.tierLabel,
    this.newReferencePrice,
    this.usedReferencePrice,
    this.crossMarketAdvice,
  });

  final double score;
  final String verdict;
  final String recommendation;
  final int referencePrice;
  final double deltaPercent;
  final int fairPriceLow;
  final int fairPriceHigh;
  final String? tierLabel;
  final int? newReferencePrice;
  final int? usedReferencePrice;
  final String? crossMarketAdvice;
}

/// Port score_price() Python.
ScoreResult scorePrice(
  int price,
  List<int> referencePrices, {
  bool isNewReference = false,
}) {
  final usable = referencePrices.where((v) => v > 0).toList();
  if (usable.isEmpty) {
    return ScoreResult(
      score: 50.0,
      verdict: 'data terbatas',
      recommendation:
          'Belum cukup pembanding untuk memberi rekomendasi kuat.',
      referencePrice: price,
      deltaPercent: 0.0,
      fairPriceLow: price,
      fairPriceHigh: price,
    );
  }

  final usableSorted = List<int>.of(usable)..sort();
  // Python: int(round(statistics.median(...))) — round half-even, BUKAN truncate.
  final reference = pyRoundInt(medianOf(usableSorted));
  final ratio = price / reference;
  final deltaPercent = pyRound((ratio - 1) * 100, 1);

  late final String verdict;
  late final String recommendation;
  late final double score;
  late final int fairLow;
  late final int fairHigh;

  if (isNewReference) {
    // Band ketat untuk referensi HARGA BARU (retail / konversi USD).
    // Barang bekas di 95% harga baru jelas kemahalan (mending beli baru bergaransi).
    fairLow = (reference * 0.65).toInt();
    fairHigh = (reference * 0.80).toInt();
    if (ratio <= 0.65) {
      verdict = 'worth it';
      recommendation =
          'Harga berada jauh di bawah estimasi harga baru dan layak dipertimbangkan.';
      score = 90 + math.min(10.0, (0.65 - ratio) * 30);
    } else if (ratio <= 0.80) {
      verdict = 'wajar';
      recommendation =
          'Harga berada di rentang wajar dibanding estimasi harga baru.';
      score = 75 + ((0.80 - ratio) / 0.15) * 15;
    } else if (ratio <= 0.90) {
      verdict = 'ada opsi lebih baik';
      recommendation =
          'Harga mendekati estimasi harga baru; pertimbangkan beli baru bergaransi atau cari opsi lain.';
      score = 60 + ((0.90 - ratio) / 0.10) * 15;
    } else {
      verdict = 'kemahalan';
      recommendation =
          'Harga terlalu dekat atau melebihi estimasi harga baru; sangat disarankan beli baru bergaransi.';
      score = 50 - (ratio - 0.90) * 80;
    }
  } else {
    if (usableSorted.length >= 4) {
      fairLow = usableSorted[usableSorted.length ~/ 4];
      fairHigh = usableSorted[(3 * usableSorted.length) ~/ 4];
    } else {
      fairLow = (reference * 0.90).toInt();
      fairHigh = (reference * 1.10).toInt();
    }

    if (ratio <= 0.90) {
      verdict = 'worth it';
      recommendation =
          'Harga berada di bawah median pasar dan layak dipertimbangkan.';
      score = 90 + math.min(10.0, (0.90 - ratio) * 30);
    } else if (ratio <= 1.10) {
      verdict = 'wajar';
      recommendation =
          'Harga masih berada di rentang wajar berdasarkan pembanding yang tersedia.';
      score = 80 - (ratio - 1).abs() * 100;
    } else if (ratio <= 1.25) {
      verdict = 'ada opsi lebih baik';
      recommendation =
          'Ada pembanding dengan harga lebih rendah; pertimbangkan negosiasi atau opsi lain.';
      score = 65 - (ratio - 1.10) * 100;
    } else {
      verdict = 'kemahalan';
      recommendation = 'Harga berada cukup jauh di atas median pasar.';
      score = 50 - (ratio - 1.25) * 80;
    }
  }

  return ScoreResult(
    score: pyRound(_clamp(score), 1),
    verdict: verdict,
    recommendation: recommendation,
    referencePrice: reference,
    deltaPercent: deltaPercent,
    fairPriceLow: fairLow,
    fairPriceHigh: fairHigh,
  );
}
