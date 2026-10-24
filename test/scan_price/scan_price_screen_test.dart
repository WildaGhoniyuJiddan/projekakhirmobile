import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:worthbang/screens/scan_price_screen.dart';
import 'package:worthbang/services/features/scan_price_parser.dart';
import 'package:worthbang/services/features/scan_price_service.dart';

/// OCR palsu: tanpa kamera/ML Kit asli. Hasil pindaian diatur per test.
class FakeScanPriceService implements IScanPriceService {
  FakeScanPriceService({required this.result});

  final ScanServiceResult result;
  ImageSource? lastSource;

  @override
  Future<ScanServiceResult> captureAndParse({
    ImageSource source = ImageSource.camera,
  }) async {
    lastSource = source;
    return result;
  }

  @override
  Future<String> recognizeTextFromFile(File imageFile) async => '';

  @override
  Future<void> dispose() async {}
}

ScanParseResult _fakeParse() => const ScanParseResult(
      query: 'RTX 4060 8GB',
      priceCandidates: [7500000, 5299000],
      defaultPrice: 5299000,
      rawText: 'RTX 4060 8GB\nRp 7.500.000\nRp 5.299.000',
    );

Future<void> _pumpScreen(
  WidgetTester tester, {
  required IScanPriceService service,
  required void Function(String query, int price) onAnalyze,
  required void Function({String? initialQuery}) onFallback,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ScanPriceScreen(
        scanService: service,
        onAnalyzeRequested: (context, query, price) async {
          onAnalyze(query, price);
        },
        onFallbackManual: (context, {initialQuery}) {
          onFallback(initialQuery: initialQuery);
        },
      ),
    ),
  );
}

void main() {
  group('ScanPriceScreen (FakeScanPriceService)', () {
    testWidgets(
        'hasil OCR lengkap langsung dianalisis otomatis tanpa ketuk Cek Worth It',
        (tester) async {
      String? gotQuery;
      int? gotPrice;
      await _pumpScreen(
        tester,
        service: FakeScanPriceService(
          result: ScanServiceResult.success(_fakeParse()),
        ),
        onAnalyze: (q, p) {
          gotQuery = q;
          gotPrice = p;
        },
        onFallback: ({initialQuery}) {},
      );

      // State guide.
      expect(find.text('Ambil Foto'), findsOneWidget);

      await tester.tap(find.text('Ambil Foto'));
      await tester.pumpAndSettle();

      // Analisis sudah terpanggil otomatis; layar konfirmasi tetap tampil
      // sebagai jaring pengaman koreksi (kembali dari layar hasil).
      expect(gotQuery, 'RTX 4060 8GB');
      expect(gotPrice, 5299000);
      expect(find.text('RTX 4060 8GB'), findsOneWidget);
      expect(find.text('5299000'), findsOneWidget);
      expect(find.text('Rp7.500.000'), findsOneWidget);
      expect(find.text('Rp5.299.000'), findsOneWidget);
    });

    testWidgets('OCR tak lengkap berhenti di konfirmasi tanpa analisis',
        (tester) async {
      String? gotQuery;
      int? gotPrice;
      await _pumpScreen(
        tester,
        service: FakeScanPriceService(
          result: ScanServiceResult.success(
            const ScanParseResult(
              query: '',
              priceCandidates: [5299000],
              defaultPrice: 5299000,
              rawText: 'Rp 5.299.000',
            ),
          ),
        ),
        onAnalyze: (q, p) {
          gotQuery = q;
          gotPrice = p;
        },
        onFallback: ({initialQuery}) {},
      );

      await tester.tap(find.text('Ambil Foto'));
      await tester.pumpAndSettle();

      // Nama kosong -> tidak auto-analisis; user melengkapi lalu ketuk manual.
      expect(gotQuery, isNull);
      expect(gotPrice, isNull);
      expect(find.text('Hasil pindaian'), findsOneWidget);
    });

    testWidgets('ganti chip harga mengubah harga yang dikirim', (tester) async {
      String? gotQuery;
      int? gotPrice;
      await _pumpScreen(
        tester,
        service: FakeScanPriceService(
          result: ScanServiceResult.success(_fakeParse()),
        ),
        onAnalyze: (q, p) {
          gotQuery = q;
          gotPrice = p;
        },
        onFallback: ({initialQuery}) {},
      );

      await tester.tap(find.text('Ambil Foto'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rp7.500.000'));
      await tester.pump();
      expect(find.text('7500000'), findsOneWidget);

      await tester.tap(find.text('Cek Worth It'));
      await tester.pumpAndSettle();

      expect(gotQuery, 'RTX 4060 8GB');
      expect(gotPrice, 7500000);
    });

    testWidgets('Pilih dari Galeri memanggil capture dengan sumber galeri',
        (tester) async {
      final service = FakeScanPriceService(
        result: ScanServiceResult.success(_fakeParse()),
      );
      await _pumpScreen(
        tester,
        service: service,
        onAnalyze: (q, p) {},
        onFallback: ({initialQuery}) {},
      );

      expect(find.text('Pilih dari Galeri'), findsOneWidget);

      await tester.tap(find.text('Pilih dari Galeri'));
      await tester.pumpAndSettle();

      expect(service.lastSource, ImageSource.gallery);
      expect(find.text('RTX 4060 8GB'), findsOneWidget);
    });

    testWidgets('state error menampilkan tombol fallback manual',
        (tester) async {
      bool fallbackCalled = false;
      await _pumpScreen(
        tester,
        service: FakeScanPriceService(
          result: ScanServiceResult.failure('OCR gagal total.'),
        ),
        onAnalyze: (q, p) {},
        onFallback: ({initialQuery}) {
          fallbackCalled = true;
        },
      );

      await tester.tap(find.text('Ambil Foto'));
      await tester.pumpAndSettle();

      expect(find.text('OCR gagal total.'), findsOneWidget);
      expect(find.text('Isi Manual'), findsOneWidget);

      await tester.tap(find.text('Isi Manual'));
      await tester.pump();
      expect(fallbackCalled, isTrue);
    });
  });
}
