import 'package:flutter_test/flutter_test.dart';
import 'package:worthbang/utils/rupiah.dart';

void main() {
  group('formatRupiah', () {
    test('memformat integer IDR dengan pemisah ribuan titik', () {
      expect(formatRupiah(4500000), 'Rp4.500.000');
    });

    test('nol dan nilai kecil', () {
      expect(formatRupiah(0), 'Rp0');
      expect(formatRupiah(500), 'Rp500');
    });

    test('nilai besar', () {
      expect(formatRupiah(15000000), 'Rp15.000.000');
    });
  });
}
