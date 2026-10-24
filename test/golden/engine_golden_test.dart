/// Golden test — jangkar kebenaran porting engine Python → Dart.
///
/// SEMUA nilai ekspektasi di file ini adalah LITERAL hasil menjalankan
/// fungsi Python asli di repo lama
/// (`WorthGaBang-AndroidVer/backend/app/services/scoring.py` &
/// `benchmark.py`, dipanen 2026-10-20). Lihat `golden_values.md` di
/// folder yang sama untuk tabel panen lengkapnya. JANGAN menghitung
/// ulang ekspektasi dengan logika yang sama — itu tautologi.
///
/// SEAM (per docs/CONTRACTS.md): fungsi top-level di
/// `lib/services/engine/scoring.dart` & `benchmark.dart`, meniru
/// semantik modul Python (dataset dimuat global via
/// `BenchmarkData.load()` di `engine/dataset.dart`, dipanggil sekali
/// di setUpAll). Field hasil memakai camelCase dari kunci Python:
/// price_usd → priceUsd, consensus_score → consensusScore,
/// n_sources → nSources, est_price_idr → estPriceIdr,
/// gain_percent → gainPercent, vram_gb → vramGb,
/// tier_label → tierLabel, is_igpu → isIgpu.
/// Bila Porter-Engine memilih bentuk seam lain, sesuaikan
/// pemanggilannya di sini — NILAI-nya tidak boleh berubah.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:worthbang/services/engine/benchmark_api.dart';
import 'package:worthbang/services/engine/dataset.dart';
import 'package:worthbang/services/engine/scoring.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await BenchmarkData.load();
  });

  group('scoring — scorePrice (mode pasar)', () {
    const refs = [4000000, 4500000, 5000000, 5500000, 6000000];

    test('jauh di bawah median → worth it 96.0', () {
      final r = scorePrice(3500000, refs);
      expect(r.score, closeTo(96.0, 0.01));
      expect(r.verdict, 'worth it');
      expect(r.referencePrice, 5000000);
      expect(r.deltaPercent, -30.0);
      expect(r.fairPriceLow, 4500000);
      expect(r.fairPriceHigh, 5500000);
      expect(r.recommendation,
          'Harga berada di bawah median pasar dan layak dipertimbangkan.');
    });

    test('pas di batas 0.90 → worth it 90.0', () {
      final r = scorePrice(4500000, refs);
      expect(r.score, closeTo(90.0, 0.01));
      expect(r.verdict, 'worth it');
      expect(r.deltaPercent, -10.0);
    });

    test('pas median → wajar 80.0', () {
      final r = scorePrice(5000000, refs);
      expect(r.score, closeTo(80.0, 0.01));
      expect(r.verdict, 'wajar');
      expect(r.deltaPercent, 0.0);
      expect(r.recommendation,
          'Harga masih berada di rentang wajar berdasarkan pembanding yang tersedia.');
    });

    test('sedikit di atas median → wajar 75.0', () {
      final r = scorePrice(5250000, refs);
      expect(r.score, closeTo(75.0, 0.01));
      expect(r.verdict, 'wajar');
      expect(r.deltaPercent, 5.0);
    });

    test('rasio 1.15 → ada opsi lebih baik 60.0', () {
      final r = scorePrice(5750000, refs);
      expect(r.score, closeTo(60.0, 0.01));
      expect(r.verdict, 'ada opsi lebih baik');
      expect(r.deltaPercent, 15.0);
    });

    test('rasio 1.40 → kemahalan 38.0', () {
      final r = scorePrice(7000000, refs);
      expect(r.score, closeTo(38.0, 0.01));
      expect(r.verdict, 'kemahalan');
      expect(r.deltaPercent, 40.0);
    });

    test('tanpa pembanding → data terbatas 50.0', () {
      final r = scorePrice(5000000, const []);
      expect(r.score, closeTo(50.0, 0.01));
      expect(r.verdict, 'data terbatas');
      expect(r.referencePrice, 5000000);
      expect(r.deltaPercent, 0.0);
      expect(r.fairPriceLow, 5000000);
      expect(r.fairPriceHigh, 5000000);
      expect(r.recommendation,
          'Belum cukup pembanding untuk memberi rekomendasi kuat.');
    });

    test('pembanding nol semua → sama seperti kosong', () {
      final r = scorePrice(5000000, const [0, 0]);
      expect(r.score, closeTo(50.0, 0.01));
      expect(r.verdict, 'data terbatas');
    });

    test('pembanding < 4 → band wajar dari median (ref*0.9–1.1)', () {
      final r = scorePrice(4700000, const [4800000, 5200000]);
      expect(r.score, closeTo(74.0, 0.01));
      expect(r.verdict, 'wajar');
      expect(r.referencePrice, 5000000);
      expect(r.deltaPercent, -6.0);
      expect(r.fairPriceLow, 4500000);
      expect(r.fairPriceHigh, 5500000);
    });

    test('median jumlah genap = rata-rata dua nilai tengah', () {
      final r = scorePrice(4500000, const [4000000, 5000000]);
      expect(r.score, closeTo(80.0, 0.01));
      expect(r.verdict, 'wajar');
      expect(r.referencePrice, 4500000);
      expect(r.fairPriceLow, 4050000);
      expect(r.fairPriceHigh, 4950000);
    });
  });

  group('scoring — scorePrice (mode referensi harga baru)', () {
    const refsBaru = [8000000];

    test('rasio 0.625 → worth it 90.8, band ketat 65–80%', () {
      final r = scorePrice(5000000, refsBaru, isNewReference: true);
      expect(r.score, closeTo(90.8, 0.01));
      expect(r.verdict, 'worth it');
      expect(r.deltaPercent, -37.5);
      expect(r.fairPriceLow, 5200000);
      expect(r.fairPriceHigh, 6400000);
    });

    test('rasio 0.75 → wajar 80.0', () {
      final r = scorePrice(6000000, refsBaru, isNewReference: true);
      expect(r.score, closeTo(80.0, 0.01));
      expect(r.verdict, 'wajar');
      expect(r.deltaPercent, -25.0);
    });

    test('rasio 0.85 → ada opsi lebih baik 67.5', () {
      final r = scorePrice(6800000, refsBaru, isNewReference: true);
      expect(r.score, closeTo(67.5, 0.01));
      expect(r.verdict, 'ada opsi lebih baik');
      expect(r.deltaPercent, -15.0);
    });

    test('rasio 0.95 → kemahalan 46.0', () {
      final r = scorePrice(7600000, refsBaru, isNewReference: true);
      expect(r.score, closeTo(46.0, 0.01));
      expect(r.verdict, 'kemahalan');
      expect(r.deltaPercent, -5.0);
    });
  });

  group('benchmark — passmarkScore', () {
    test('RTX 4060 → GeForce RTX 4060, 19489', () {
      final e = passmarkScore('RTX 4060', 'gpu');
      expect(e, isNotNull);
      expect(e!.name, 'GeForce RTX 4060');
      expect(e.score, 19489);
      expect(e.priceUsd, 479.0);
    });

    test('huruf kecil + varian Ti tetap ketemu', () {
      final e = passmarkScore('rtx 4060 ti', 'gpu');
      expect(e!.name, 'GeForce RTX 4060 Ti');
      expect(e.score, 22599);
      expect(e.priceUsd, 529.0);
    });

    test('RTX 3060 tidak punya harga USD di katalog', () {
      final e = passmarkScore('RTX 3060', 'gpu');
      expect(e!.name, 'GeForce RTX 3060');
      expect(e.score, 16895);
      expect(e.priceUsd, isNull);
    });

    test('GTX 1660 Super → nama katalog kapital SUPER', () {
      final e = passmarkScore('GTX 1660 Super', 'gpu');
      expect(e!.name, 'GeForce GTX 1660 SUPER');
      expect(e.score, 12662);
      expect(e.priceUsd, 242.8);
    });

    test('RTX 4090 → 38043', () {
      final e = passmarkScore('RTX 4090', 'gpu');
      expect(e!.score, 38043);
      expect(e.priceUsd, 3299.95);
    });

    test('CPU Ryzen 5 5600 & 7800X3D', () {
      expect(passmarkScore('Ryzen 5 5600', 'cpu')!.score, 21494);
      expect(passmarkScore('Ryzen 5 5600', 'cpu')!.priceUsd, 126.47);
      expect(passmarkScore('Ryzen 7 7800X3D', 'cpu')!.score, 34276);
      expect(passmarkScore('Ryzen 7 7800X3D', 'cpu')!.priceUsd, 319.98);
    });

    test('nama ngawur → null; tipe salah → null', () {
      expect(passmarkScore('Komponen Ngawur', 'gpu'), isNull);
      expect(passmarkScore('RTX 4060', 'ram'), isNull);
    });

    test('label tier PassMark', () {
      expect(getTierLabel(30000, 'gpu'), 'Enthusiast (4K Ultra Gaming)');
      expect(getTierLabel(15000, 'gpu'), 'Midrange (1080p Ultra / 1440p Mid)');
      expect(getTierLabel(5000, 'gpu'), 'Basic (Office & Casual)');
      expect(getTierLabel(40000, 'cpu'),
          'High End (Heavy Productivity & Gaming)');
      expect(getTierLabel(15000, 'cpu'), 'Budget (1080p Gaming & Daily Work)');
      expect(getTierLabel(25000, 'laptop'), 'High End Gaming / Workstation');
      expect(getTierLabel(0, 'gpu'), 'Standard');
    });
  });

  group('consensus — consensusLookup & tier', () {
    test('RTX 4060 → skor konsensus RENDAH 28.97 (quirk percentile)', () {
      final e = consensusLookup('RTX 4060', 'gpu');
      expect(e, isNotNull);
      expect(e!.name, 'Nvidia RTX 4060');
      expect(e.consensusScore, closeTo(28.97, 0.001));
      expect(e.tier, 'C');
      expect(e.nSources, 7);
      expect(e.agreement, closeTo(20.45, 0.001));
      expect(e.priceUsd, 245.0);
    });

    test('RTX 4060 Ti → 85.25 tier S dari 1 sumber', () {
      final e = consensusLookup('rtx 4060 ti', 'gpu');
      expect(e!.name, 'Nvidia RTX 4060-Ti');
      expect(e.consensusScore, closeTo(85.25, 0.001));
      expect(e.tier, 'S');
      expect(e.nSources, 1);
    });

    test('RTX 3060 → 75.41 tier A', () {
      final e = consensusLookup('RTX 3060', 'gpu');
      expect(e!.consensusScore, closeTo(75.41, 0.001));
      expect(e.tier, 'A');
    });

    test('GTX 1660 Super TIDAK ada di dataset konsensus → null', () {
      expect(consensusLookup('GTX 1660 Super', 'gpu'), isNull);
    });

    test('RTX 4090 → 97.12 tier S, 8 sumber', () {
      final e = consensusLookup('RTX 4090', 'gpu');
      expect(e!.consensusScore, closeTo(97.12, 0.001));
      expect(e.tier, 'S');
      expect(e.nSources, 8);
    });

    test('CPU: Ryzen 5 5600 → 57.91 B; 7800X3D → 78.08 A', () {
      final a = consensusLookup('Ryzen 5 5600', 'cpu');
      expect(a!.consensusScore, closeTo(57.91, 0.001));
      expect(a.tier, 'B');
      expect(a.nSources, 4);
      final b = consensusLookup('Ryzen 7 7800X3D', 'cpu');
      expect(b!.consensusScore, closeTo(78.08, 0.001));
      expect(b.tier, 'A');
      expect(b.nSources, 5);
    });

    test('nama ngawur → null; tipe salah → null', () {
      expect(consensusLookup('Komponen Ngawur', 'gpu'), isNull);
      expect(consensusLookup('RTX 4060', 'ram'), isNull);
    });

    test('label tier konsensus (Indonesia)', () {
      expect(consensusTierLabel(85.0), 'Kelas Atas (High End)');
      expect(consensusTierLabel(65.0), 'Menengah Atas (Upper Midrange)');
      expect(consensusTierLabel(45.0), 'Menengah (Midrange)');
      expect(consensusTierLabel(25.0), 'Pemula (Entry Level)');
      expect(consensusTierLabel(10.0), 'Dasar (Basic)');
      expect(consensusTierLabel(null), 'Standard');
    });
  });

  group('benchmark — betterAlternatives (PassMark)', () {
    test('GPU di harga ini → kosong (filter harga menyapu kandidat)', () {
      expect(betterAlternatives('RTX 3060', 'gpu', 6000000, 16000), isEmpty);
      expect(betterAlternatives('RTX 4060', 'gpu', 5500000, 16000), isEmpty);
    });

    test('Ryzen 5 5600 @2.5jt → Ryzen 9 3900X (+51%)', () {
      final alts = betterAlternatives('Ryzen 5 5600', 'cpu', 2500000, 16000);
      expect(alts, hasLength(1));
      expect(alts.first.name, 'AMD Ryzen 9 3900X');
      expect(alts.first.score, 32475);
      expect(alts.first.estPriceIdr, 2410320);
      expect(alts.first.gainPercent, 51);
      expect(alts.first.tierLabel, 'High End (Heavy Productivity & Gaming)');
    });

    test('nama ngawur → kosong', () {
      expect(
          betterAlternatives('Komponen Ngawur', 'gpu', 5000000, 16000),
          isEmpty);
    });
  });

  group('consensus — betterAlternativesConsensus', () {
    test('RTX 3060 @6jt → kosong (tak ada kandidat +10 poin masuk budget)',
        () {
      expect(
          betterAlternativesConsensus('RTX 3060', 'gpu', 6000000, 16000),
          isEmpty);
    });

    test('RTX 4060 @5.5jt → RTX 3060 lalu RTX 2060 (modern didahulukan)',
        () {
      // PENYIMPANGAN SENGAJA dari urutan skor mentah Python (Okt 2026):
      // kebijakan alternatif GPU mendahulukan arsitektur modern (RTX)
      // di atas GTX lawas. NILAI (skor, harga, gain, sumber) tetap sama
      // persis dengan panen Python; hanya urutannya yang berubah, dan
      // GTX 1080-Ti (skor mentah 78, tertinggi) kini jatuh ke urutan 3
      // karena dua slot teratas diisi kandidat modern.
      final alts =
          betterAlternativesConsensus('RTX 4060', 'gpu', 5500000, 16000);
      expect(alts, hasLength(2));
      expect(alts[0].name, 'Nvidia RTX 3060');
      expect(alts[0].score, 75);
      expect(alts[0].estPriceIdr, 4928000);
      expect(alts[0].gainPercent, 160);
      expect(alts[0].vramGb, 12);
      expect(alts[1].name, 'Nvidia RTX 2060');
      expect(alts[1].score, 66);
      expect(alts[1].estPriceIdr, 2464000);
      expect(alts[1].gainPercent, 128);
      expect(alts[1].vramGb, 6);
      expect(alts[1].nSources, 1);
    });

    test('Ryzen 5 5600 @2.5jt → 5500GT lalu i5-12600', () {
      final alts =
          betterAlternativesConsensus('Ryzen 5 5600', 'cpu', 2500000, 16000);
      expect(alts, hasLength(2));
      expect(alts[0].name, 'AMD Ryzen 5 5500GT');
      expect(alts[0].score, 80);
      expect(alts[0].estPriceIdr, 2376000);
      expect(alts[0].gainPercent, 38);
      expect(alts[1].name, 'Intel Core i5-12600');
      expect(alts[1].score, 77);
      expect(alts[1].estPriceIdr, 2428800);
      expect(alts[1].gainPercent, 34);
      expect(alts[1].nSources, 3);
    });

    test('nama ngawur → kosong', () {
      expect(
          betterAlternativesConsensus(
              'Komponen Ngawur', 'gpu', 5000000, 16000),
          isEmpty);
    });
  });

  group('benchmark — laptopComboScore', () {
    test('gaming: 65% GPU + 35% CPU (CPU desktop → proksi mobile 5600H)', () {
      final c = laptopComboScore('Ryzen 5 5600', 'RTX 4060');
      expect(c, isNotNull);
      expect(c!.score, 18395);
      expect(c.isIgpu, isFalse);
      expect(c.tierLabel, 'Midrange Gaming / Content Creation');
      expect(c.gpu?.name, 'GeForce RTX 4060');
      // Quirk Python asli: resolve_cpu_laptop memeriksa katalog MOBILE
      // lebih dulu, jadi "Ryzen 5 5600" terpetakan ke 5600H.
      expect(c.cpu?.name, 'AMD Ryzen 5 5600H');
    });

    test('CPU laptop asli i5-12450H + RTX 3050 → 12542', () {
      final c = laptopComboScore('Core i5-12450H', 'RTX 3050');
      expect(c!.score, 12542);
      expect(c.isIgpu, isFalse);
      expect(c.tierLabel, 'Budget Gaming / Fast Productivity');
      expect(c.gpu?.name, 'GeForce RTX 3050 6GB');
      expect(c.cpu?.name, 'Intel Core i5-12450H');
    });

    test('iGPU Iris Xe: CPU tak terpetakan, skor = skor GPU saja', () {
      final c = laptopComboScore('Core i7-1165G7', 'Intel Iris Xe Graphics');
      expect(c!.score, 2590);
      expect(c.isIgpu, isTrue);
      expect(c.tierLabel, 'Ultrabook / Daily Office');
      expect(c.cpu, isNull);
    });

    test('dua-duanya ngawur → null', () {
      expect(laptopComboScore('Komponen Ngawur', 'GPU Ngawur'), isNull);
    });
  });

  group('benchmark — extractVramGb', () {
    test('dari string eksplisit & aturan hardcoded', () {
      expect(extractVramGb('RTX 4060 8GB'), 8);
      expect(extractVramGb('RTX 3060'), 12);
      expect(extractVramGb('RX 6700 XT'), 12);
      expect(extractVramGb('RTX 4070 Ti 16GB'), 16);
      expect(extractVramGb('GTX 1650'), 4);
      expect(extractVramGb('RX 6800'), 16);
      expect(extractVramGb('RTX 2060 Super'), 8);
    });

    test('tanpa petunjuk → null (termasuk RTX 4090 polos)', () {
      expect(extractVramGb('RTX 4090'), isNull);
      expect(extractVramGb('Kartu Polos'), isNull);
    });
  });
}
