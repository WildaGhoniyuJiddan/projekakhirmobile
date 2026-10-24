/// Fixture transkrip OCR P4 + tes advice engine untuk query hasil scan.
///
/// (Okt 2026, perintah Dan): fixture untuk 4 layout — Tokopedia,
/// Shopee, Facebook Marketplace, label fisik — dengan nama toko/penjual
/// dan nomor HP diganti placeholder ([NAMA_TOKO], [NAMA_PENJUAL],
/// 08XXXXXXXXXX). Nama toko kasus nyata TIDAK muncul
/// di fixture mana pun. Setiap fixture harus lolos P1 (nama mengandung
/// token model, tanpa placeholder toko) dan P2 bila relevan (pasangan
/// promo-coret -> harga kecil).
///
/// Tes advice memakai engine nyata (BenchmarkData asli + listings
/// kosong) pada query hasil scan Tokopedia @Rp950.000, kondisi 'any'
/// (default jalur scan). Expected diambil dari perilaku engine di
/// bawah aturan PassMark baru, bukan karangan (lihat probe P4):
/// tidak ada alternatif — tidak ada kartu di katalog yang PassMark-nya
/// >= 10% di atas GTX 1050 Ti (6366) sekaligus muat budget estimasi
/// ~Rp863rb — sehingga rekomendasi murni teks anchor 'worth it'.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:worthbang/services/engine/analysis_engine.dart';
import 'package:worthbang/services/engine/dataset.dart';
import 'package:worthbang/services/features/scan_price_parser.dart';

class _EmptyListings implements ListingsSource {
  @override
  Future<List<ListingRow>> pcListings({
    String? modelNum,
    required List<String> categories,
  }) async =>
      [];

  @override
  Future<List<Map<String, Object?>>> laptopUnits({
    required List<String> tokens,
  }) async =>
      [];

  @override
  Future<List<Map<String, Object?>>> pcComponents({
    required List<String> tokens,
  }) async =>
      [];

  @override
  Future<DateTime?> latestScrapedAt() async => null;
}

/// Layout kartu produk Tokopedia: toko, judul + spek, harga promo +
/// harga coret, tombol beli, lokasi.
const _tokopedia = '''
[NAMA_TOKO]
Colorful GTX 1050 TI
4GB GDDR5 No Pin Power
Rp950.000
Rp1.000.000
Beli Sekarang
Jakarta Selatan''';

/// Layout kartu produk Shopee: judul + spek, harga promo + coret,
/// toko, tombol chat, nomor HP placeholder.
const _shopee = '''
Colorful GTX 1050 TI 4GB GDDR5
Rp950.000
Rp1.000.000
[NAMA_TOKO]
Chat
08XXXXXXXXXX''';

/// Layout listing Facebook Marketplace: judul + spek, harga tunggal,
/// lokasi, penjual placeholder, tombol kirim pesan, nomor HP placeholder.
const _facebook = '''
Colorful GTX 1050 TI
4GB GDDR5
Rp950.000
Kota Yogyakarta
[NAMA_PENJUAL]
Kirim Pesan
08XXXXXXXXXX''';

/// Layout label fisik toko: merek, tipe + spek, harga, garansi.
const _labelFisik = '''
COLORFUL
GTX 1050 TI 4GB
GDDR5
Rp950.000
Garansi 1 Tahun''';

void main() {
  group('fixture OCR P4: parse lolos P1 (+ P2 bila relevan)', () {
    test('Tokopedia: query bertoken, default = promo (P2 95%)', () {
      final p = ScanPriceParser.parseScan(_tokopedia);
      expect(p.query, 'Colorful GTX 1050 TI 4GB GDDR5 No Pin Power');
      expect(p.query, contains('GTX 1050'));
      expect(p.query, isNot(contains('NAMA_TOKO')));
      expect(p.priceCandidates, [950000, 1000000]);
      expect(p.defaultPrice, 950000);
    });

    test('Shopee: query bertoken, default = promo (P2 95%)', () {
      final p = ScanPriceParser.parseScan(_shopee);
      expect(p.query, 'Colorful GTX 1050 TI 4GB GDDR5');
      expect(p.query, contains('GTX 1050'));
      expect(p.query, isNot(contains('NAMA_TOKO')));
      expect(p.query, isNot(contains('08X')));
      expect(p.priceCandidates, [950000, 1000000]);
      expect(p.defaultPrice, 950000);
    });

    test('Facebook Marketplace: query bertoken, harga tunggal', () {
      final p = ScanPriceParser.parseScan(_facebook);
      expect(p.query, 'Colorful GTX 1050 TI 4GB GDDR5');
      expect(p.query, contains('GTX 1050'));
      expect(p.query, isNot(contains('NAMA_PENJUAL')));
      expect(p.query, isNot(contains('08X')));
      expect(p.priceCandidates, [950000]);
      expect(p.defaultPrice, 950000);
    });

    test('label fisik: merek + tipe + spek, harga tunggal', () {
      final p = ScanPriceParser.parseScan(_labelFisik);
      expect(p.query, 'COLORFUL GTX 1050 TI 4GB GDDR5');
      expect(p.query, contains('GTX 1050'));
      expect(p.priceCandidates, [950000]);
      expect(p.defaultPrice, 950000);
    });
  });

  group('advice engine untuk query hasil scan 1050 TI @950rb', () {
    test('tidak ada alternatif benchmark; rekomendasi anchor worth it',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final data = await BenchmarkData.load();
      final query =
          ScanPriceParser.parseScan(_tokopedia).query;
      final engine = AnalysisEngine(data, _EmptyListings());
      final out = await engine.analyze(AnalyzeRequestData(
        mode: 'pc',
        query: query,
        price: 950000,
        componentType: 'gpu',
        condition: 'any',
      ));
      // Perilaku engine nyata di bawah aturan PassMark baru (probe P4):
      // anchor retail 1050 TI = 2,3jt menahan jalur ML; skor 97,1 dari
      // scorePrice atas anchor; tidak ada alternatif yang lolos ambang
      // 10% + budget, sehingga advice kosong.
      // ALASAN PERUBAHAN (P5, Okt 2026, perintah Dan): advice kosong
      // kini eksplisit. CATATAN PENTING dari probe P5: lookup benchmark
      // (PassMark maupun konsensus) TIDAK me-resolve query lengkap
      // hasil P1 ('Colorful GTX 1050 TI 4GB GDDR5 No Pin Power' ->
      // null), hanya bentuk pendek 'GTX 1050 TI' (PassMark 6366).
      // Jadi untuk query scan lengkap, pesan yang muncul adalah yang
      // "tidak dikenali" — ini celah nyata resolusi query (anchor
      // justru me-resolve-nya), DILAPORKAN ke Dan dan TIDAK diperbaiki
      // di fase ini (di luar scope P5). Nilai anchor/verdict/skor
      // tidak berubah.
      expect(out.result.verdict, 'worth it');
      expect(out.result.score, 97.1);
      expect(out.result.referencePrice, 2300000);
      expect(out.alternatives, isEmpty);
      expect(out.result.recommendation,
          'Harga berada jauh di bawah estimasi harga baru dan layak dipertimbangkan. '
          'Model ini tidak dikenali di data benchmark, jadi tidak ada alternatif yang bisa disarankan.');
    });
  });
}
