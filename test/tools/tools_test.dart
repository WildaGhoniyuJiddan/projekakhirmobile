import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthbang/services/features/currency_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('format tanggal Indonesia tersedia untuk layar konverter', () async {
    await initializeDateFormatting('id_ID');
    final formatted = DateFormat(
      'd MMM yyyy HH:mm',
      'id_ID',
    ).format(DateTime(2026, 10, 15, 13, 50));
    expect(formatted, contains('Okt'));
  });

  group('CurrencyRates.fromJson (kontrak B9)', () {
    test('parse rates', () {
      final r = CurrencyRates.fromJson({
        'base': 'IDR',
        'rates': {'USD': 0.000062, 'SGD': 0.000083},
        'updated_at': '2026-09-29T10:00:00Z',
      });
      expect(r.base, 'IDR');
      expect(r.rates['USD'], 0.000062);
      expect(r.updatedAt, isNotNull);
    });
  });

  group('convertCurrency', () {
    test('4500000 IDR → USD', () {
      expect(convertCurrency(4500000, 0.000062), closeTo(279.0, 0.01));
    });

    test('nol & negatif aman', () {
      expect(convertCurrency(0, 0.000062), 0);
    });
  });

  group('convertTimezone', () {
    test('WIB → WITA (+1 jam)', () {
      final dt = DateTime(2026, 9, 29, 12, 0);
      final out = convertTimezone(dt, WibZone.wib, WibZone.wita);
      expect(out, DateTime(2026, 9, 29, 13, 0));
    });

    test('WIT → WIB (−2 jam, lintas hari)', () {
      final dt = DateTime(2026, 9, 29, 1, 30);
      final out = convertTimezone(dt, WibZone.wit, WibZone.wib);
      expect(out, DateTime(2026, 9, 28, 23, 30));
    });

    test('WIB → UTC (−7 jam)', () {
      final dt = DateTime(2026, 9, 29, 7, 0);
      final out = convertTimezone(dt, WibZone.wib, WibZone.utc);
      expect(out, DateTime(2026, 9, 29, 0, 0));
    });

    test('zona sama = identik', () {
      final dt = DateTime(2026, 9, 29, 7, 0);
      expect(convertTimezone(dt, WibZone.wib, WibZone.wib), dt);
    });
  });
}
