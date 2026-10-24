import 'package:flutter_test/flutter_test.dart';
import 'package:worthbang/services/features/scan_price_parser.dart';

void main() {
  group('ScanPriceParser.parseScan', () {
    test('label rapi satu harga', () {
      final r = ScanPriceParser.parseScan('RTX 4060 8GB\nRp 5.299.000');
      expect(r.query, 'RTX 4060 8GB');
      expect(r.priceCandidates, [5299000]);
      expect(r.defaultPrice, 5299000);
      expect(r.isReadyToAnalyze, isTrue);
    });

    test('label promo dua harga tanpa label: default = harga terakhir', () {
      final r = ScanPriceParser.parseScan(
        'RTX 4060\nRp 7.500.000\nRp 5.299.000',
      );
      expect(r.priceCandidates, [7500000, 5299000]);
      expect(r.defaultPrice, 5299000);
    });

    test('label promo berlabel DISKON: harga promo jadi kandidat, bukan default', () {
      final r = ScanPriceParser.parseScan(
        'RTX 4060\nRp 7.500.000\nDISKON Rp 5.299.000',
      );
      expect(r.priceCandidates, [7500000, 5299000]);
      // Baris sekunder tidak boleh jadi default selama ada harga utama bersih.
      expect(r.defaultPrice, 7500000);
    });

    test('jebakan cicilan/DP: angka cicilan tidak jadi default', () {
      final cicilan = ScanPriceParser.parseScan(
        'CICILAN Rp 450.000 /BLN\nRTX 4060\nRp 5.299.000',
      );
      expect(cicilan.priceCandidates, [450000, 5299000]);
      expect(cicilan.defaultPrice, 5299000);

      final dp = ScanPriceParser.parseScan(
        'DP Rp 500.000\nRTX 4060\nRp 5.299.000',
      );
      expect(dp.priceCandidates, [500000, 5299000]);
      expect(dp.defaultPrice, 5299000);
    });

    test('simbol Rp terpisah baris dari angka', () {
      final r = ScanPriceParser.parseScan('RTX 4060\nRp\n5.299.000');
      expect(r.priceCandidates, [5299000]);
      expect(r.defaultPrice, 5299000);
    });

    test('typo OCR: O jadi 0 dan l jadi 1 di dalam blok angka', () {
      final oCase = ScanPriceParser.parseScan('RTX 4060\nRp 5.299.OOO');
      expect(oCase.defaultPrice, 5299000);

      final lCase = ScanPriceParser.parseScan('SSD 1TB\nRp l.250.000');
      expect(lCase.defaultPrice, 1250000);
    });

    test('label tanpa harga: siap diisi manual, bukan siap analyze', () {
      final r = ScanPriceParser.parseScan('RTX 4060 8GB');
      expect(r.query, 'RTX 4060 8GB');
      expect(r.priceCandidates, isEmpty);
      expect(r.defaultPrice, isNull);
      expect(r.hasAnyData, isTrue);
      expect(r.isReadyToAnalyze, isFalse);
    });

    test('label tanpa nama: harga tetap diekstrak', () {
      final r = ScanPriceParser.parseScan('Rp 5.299.000');
      expect(r.query, isEmpty);
      expect(r.priceCandidates, [5299000]);
      expect(r.defaultPrice, 5299000);
      expect(r.isReadyToAnalyze, isFalse);
    });

    test('merek dan tipe dua baris digabung jadi satu query', () {
      final r = ScanPriceParser.parseScan(
        'SAMSUNG\nSSD 980 PRO 1TB NVME\nRp 1.250.000',
      );
      expect(r.query, 'SAMSUNG SSD 980 PRO 1TB NVME');
      expect(r.defaultPrice, 1250000);
    });

    test('baris SKU/barcode dan tanggal cetak dibuang dari nama', () {
      final r = ScanPriceParser.parseScan(
        '8992761134021\n24/10/2026\nRTX 4060\nRp 5.299.000',
      );
      expect(r.query, 'RTX 4060');
      expect(r.defaultPrice, 5299000);
    });

    test('harga di luar rentang 50rb-150jt dibuang', () {
      final r = ScanPriceParser.parseScan(
        'RTX 4060\nRp 25.000\nRp 250.000.000',
      );
      expect(r.priceCandidates, isEmpty);
      expect(r.defaultPrice, isNull);
      expect(r.query, 'RTX 4060');
    });

    test('teks kosong menghasilkan hasil kosong', () {
      final r = ScanPriceParser.parseScan('   \n  ');
      expect(r.query, isEmpty);
      expect(r.priceCandidates, isEmpty);
      expect(r.defaultPrice, isNull);
      expect(r.hasAnyData, isFalse);
    });
  });
}
