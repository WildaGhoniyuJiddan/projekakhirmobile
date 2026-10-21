import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthbang/providers/providers.dart';
import 'package:worthbang/services/core/api_client.dart';

final currencyApiProvider = Provider<CurrencyApi>(
  (ref) => CurrencyApi(ref.watch(apiClientProvider)),
);

/// Kurs — sekarang langsung ke API FX publik (tanpa via backend),
/// dengan fallback konstanta bila offline.
class CurrencyApi {
  CurrencyApi(this._client);

  final ApiClient _client;

  static const _fxUrl = 'https://open.er-api.com/v1/latest/IDR';

  /// Kurs per 1 IDR (mis. 1 IDR = x USD). Offline → fallback.
  static const fallbackRates = {
    'USD': 0.000062,
    'SGD': 0.000083,
    'MYR': 0.00029,
  };

  Future<CurrencyRates> getRates({String base = 'IDR'}) async {
    try {
      final json = await _client.getJson(_fxUrl);
      final r = (json['rates'] as Map?)?.cast<String, dynamic>() ?? {};
      final rates = <String, double>{};
      for (final k in ['USD', 'SGD', 'MYR']) {
        final v = r[k];
        if (v is num) rates[k] = v.toDouble();
      }
      if (rates.isNotEmpty) {
        return CurrencyRates(
          base: base,
          rates: rates,
          updatedAt: DateTime.now(),
        );
      }
    } catch (_) {
      // Offline / API down → fallback di bawah.
    }
    return CurrencyRates(
      base: base,
      rates: Map<String, double>.from(fallbackRates),
    );
  }
}

class CurrencyRates {
  const CurrencyRates({
    required this.base,
    required this.rates,
    this.updatedAt,
  });

  final String base;
  final Map<String, double> rates;
  final DateTime? updatedAt;

  factory CurrencyRates.fromJson(Map<String, dynamic> json) {
    final r = (json['rates'] as Map?)?.cast<String, dynamic>() ?? {};
    DateTime? updated;
    final u = json['updated_at'] as String?;
    if (u != null) updated = DateTime.tryParse(u);
    return CurrencyRates(
      base: json['base'] as String? ?? 'IDR',
      rates: r.map((k, v) => MapEntry(k, (v as num).toDouble())),
      updatedAt: updated,
    );
  }
}

/// Konversi nominal: rates dinyatakan per 1 [base] (mis. 1 IDR = x USD).
double convertCurrency(double amount, double rate) => amount * rate;

/// Zona waktu Indonesia (offset jam dari UTC) + London.
enum WibZone {
  wib('WIB', 7),
  wita('WITA', 8),
  wit('WIT', 9),
  london('London', 0),
  utc('UTC', 0);

  const WibZone(this.label, this.offsetHours);
  final String label;

  /// Offset tetap zona ini. Untuk [WibZone.london] nilai ini hanya
  /// offset musim dingin; offset efektifnya bergantung tanggal,
  /// lihat [londonOffsetHours].
  final int offsetHours;
}

/// Offset London dari UTC (jam) pada [date]: +1 selama British Summer
/// Time (Minggu terakhir Maret 01:00 UTC s.d. Minggu terakhir Oktober
/// 01:00 UTC), selain itu +0. Komponen tanggal/jam [date] diperlakukan
/// sebagai UTC agar hasil deterministik di zona perangkat mana pun.
int londonOffsetHours(DateTime date) {
  final utc = DateTime.utc(
      date.year, date.month, date.day, date.hour, date.minute, date.second);
  final start = _lastSundayOfMonthUtc(utc.year, DateTime.march);
  final end = _lastSundayOfMonthUtc(utc.year, DateTime.october);
  return (!utc.isBefore(start) && utc.isBefore(end)) ? 1 : 0;
}

/// Minggu terakhir bulan [month] pukul 01:00 UTC (batas pergantian BST).
DateTime _lastSundayOfMonthUtc(int year, int month) {
  final lastDay = DateTime.utc(year, month + 1, 0, 1);
  return lastDay.subtract(Duration(days: lastDay.weekday % 7));
}

/// Offset efektif [zone] pada instan UTC [utc] (London sadar tanggal).
int effectiveOffsetHours(WibZone zone, DateTime utc) =>
    zone == WibZone.london ? londonOffsetHours(utc) : zone.offsetHours;

/// Jam dinding di [zone] untuk instan UTC [utc].
DateTime zonedTime(DateTime utc, WibZone zone) =>
    utc.add(Duration(hours: effectiveOffsetHours(zone, utc)));

/// Konversi waktu antar zona: [dt] dianggap sudah dalam zona [from].
DateTime convertTimezone(DateTime dt, WibZone from, WibZone to) {
  final fromOffset =
      from == WibZone.london ? londonOffsetHours(dt) : from.offsetHours;
  final utc = dt.subtract(Duration(hours: fromOffset));
  return utc.add(Duration(hours: effectiveOffsetHours(to, utc)));
}
