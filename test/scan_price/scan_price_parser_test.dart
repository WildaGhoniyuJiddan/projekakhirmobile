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

  group('ScanPriceParser P1 nama bertoken', () {
    test('kasus foto 1050 TI: nama toko + kategori terbuang, judul terpilih', () {
      // Transkrip kartu marketplace (nama toko sudah placeholder, sesuai
      // aturan privasi fixture): baris 1-2 adalah toko/kategori, judul di 3-4.
      final r = ScanPriceParser.parseScan(
        '[NAMA_TOKO]\nKomponen Komputer\nColorful GTX 1050 TI\n4gb GDRR5 no pin p\nRp 950.000\nRp 1.000.000\ntoko.id/listing/colorful-gtx-1050\nBuka',
      );
      expect(r.query, 'Colorful GTX 1050 TI 4gb GDRR5 no pin p');
      expect(r.query, contains('GTX 1050'));
      expect(r.query, isNot(contains('NAMA_TOKO')));
      expect(r.query, isNot(contains('Komponen')));
      expect(r.query, isNot(contains('Buka')));
      expect(r.query, isNot(contains('toko.id')));
    });

    test('baris toko dan URL dibuang, baris bertoken jadi inti', () {
      final r = ScanPriceParser.parseScan(
        'Berkah Shop\nRTX 4060 8GB\nRp 5.299.000',
      );
      expect(r.query, 'RTX 4060 8GB');

      final url = ScanPriceParser.parseScan(
        'RTX 4060\nBuka\ntoko.id/listing/rtx-4060\nRp 5.299.000',
      );
      expect(url.query, 'RTX 4060');
    });

    test('merek pendek sebelum baris bertoken tetap ikut', () {
      final r = ScanPriceParser.parseScan(
        'Toko Jaya\nASUS\nROG STRIX RTX 4060\nRp 5.299.000',
      );
      expect(r.query, 'ASUS ROG STRIX RTX 4060');
    });

    test('token mencakup CPU, RAM, storage, chipset, seri laptop', () {
      expect(
        ScanPriceParser.parseScan('Ryzen 5 5600\nRp 1.500.000').query,
        'Ryzen 5 5600',
      );
      expect(
        ScanPriceParser.parseScan('DDR5 32GB Kit\nRp 1.200.000').query,
        'DDR5 32GB Kit',
      );
      expect(
        ScanPriceParser.parseScan('SSD NVMe 1TB Gen4\nRp 900.000').query,
        'SSD NVMe 1TB Gen4',
      );
      expect(
        ScanPriceParser.parseScan('MSI B550 Tomahawk\nRp 1.800.000').query,
        'MSI B550 Tomahawk',
      );
      expect(
        ScanPriceParser.parseScan('ThinkPad X1 Carbon\nRp 12.000.000').query,
        'ThinkPad X1 Carbon',
      );
    });

    test('fallback tanpa token: aturan lama pada baris tersaring', () {
      final r = ScanPriceParser.parseScan('Kabel HDMI\n2 Meter\nRp 150.000');
      expect(r.query, 'Kabel HDMI 2 Meter');

      // Tanpa token apa pun dan hanya baris toko: query kosong, bukan nama toko.
      final storeOnly = ScanPriceParser.parseScan('Berkah Shop\nRp 150.000');
      expect(storeOnly.query, isEmpty);
    });
  });

  group('ScanPriceParser P2 pasangan promo-coret', () {
    test('pasangan 95% -> pilih yang kecil (promo)', () {
      final r = ScanPriceParser.parseScan(
        'Colorful GTX 1050 TI\nRp 950.000\nRp 1.000.000',
      );
      expect(r.priceCandidates, [950000, 1000000]);
      expect(r.defaultPrice, 950000);
    });

    test('batas inklusif 50% dan 98% -> pilih yang kecil', () {
      final half = ScanPriceParser.parseScan(
        'RTX 4060\nRp 500.000\nRp 1.000.000',
      );
      expect(half.defaultPrice, 500000);

      final edge = ScanPriceParser.parseScan(
        'RTX 4060\nRp 980.000\nRp 1.000.000',
      );
      expect(edge.defaultPrice, 980000);
    });

    test('49% -> aturan lama (primary terakhir)', () {
      final r = ScanPriceParser.parseScan(
        'RTX 4060\nRp 490.000\nRp 1.000.000',
      );
      expect(r.defaultPrice, 1000000);
    });

    test('99% -> aturan lama (primary terakhir)', () {
      final r = ScanPriceParser.parseScan(
        'RTX 4060\nRp 990.000\nRp 1.000.000',
      );
      expect(r.defaultPrice, 1000000);
    });

    test('3 kandidat primary -> aturan lama (primary terakhir)', () {
      final r = ScanPriceParser.parseScan(
        'RTX 4060\nRp 1.000.000\nRp 950.000\nRp 900.000',
      );
      expect(r.defaultPrice, 900000);
    });

    test('tunggal dan secondary-only tidak berubah', () {
      final single = ScanPriceParser.parseScan('RTX 4060\nRp 5.299.000');
      expect(single.defaultPrice, 5299000);

      final secondaryOnly =
          ScanPriceParser.parseScan('CICILAN Rp 450.000 /BLN');
      expect(secondaryOnly.defaultPrice, 450000);
    });
  });
}
