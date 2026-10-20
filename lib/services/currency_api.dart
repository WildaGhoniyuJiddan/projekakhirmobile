import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthbang/providers/providers.dart';
import 'package:worthbang/services/api_client.dart';

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

/// Zona waktu Indonesia (offset jam dari UTC).
enum WibZone {
  wib('WIB', 7),
  wita('WITA', 8),
  wit('WIT', 9),
  utc('UTC', 0);

  const WibZone(this.label, this.offsetHours);
  final String label;
  final int offsetHours;
}

/// Konversi waktu antar zona: [dt] dianggap sudah dalam zona [from].
DateTime convertTimezone(DateTime dt, WibZone from, WibZone to) {
  final utc = dt.subtract(Duration(hours: from.offsetHours));
  return utc.add(Duration(hours: to.offsetHours));
}
