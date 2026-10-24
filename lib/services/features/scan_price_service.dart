import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'scan_price_parser.dart';

/// Provider IScanPriceService untuk aplikasi (dapat di-override di test).
final scanPriceServiceProvider = Provider<IScanPriceService>((ref) {
  final service = MlKitScanPriceService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Kontrak hasil operasi Pindai Harga, seragam dengan pola ApiResult di aplikasi.
class ScanServiceResult {
  final bool isSuccess;
  final bool isCancelled;
  final ScanParseResult? data;
  final String? errorMessage;

  const ScanServiceResult._({
    required this.isSuccess,
    this.isCancelled = false,
    this.data,
    this.errorMessage,
  });

  factory ScanServiceResult.success(ScanParseResult data) =>
      ScanServiceResult._(isSuccess: true, data: data);

  factory ScanServiceResult.cancelled() =>
      const ScanServiceResult._(isSuccess: false, isCancelled: true);

  factory ScanServiceResult.failure(String message) =>
      ScanServiceResult._(isSuccess: false, errorMessage: message);
}

/// Interface abstrak supaya mudah di-mock pada widget test.
abstract class IScanPriceService {
  Future<ScanServiceResult> captureAndParse({
    ImageSource source = ImageSource.camera,
  });

  Future<String> recognizeTextFromFile(File imageFile);

  Future<void> dispose();
}

/// Implementasi produksi menggunakan ImagePicker + Google ML Kit Text Recognition.
/// OCR berjalan 100% on-device (bukan LLM, tanpa token, tanpa jaringan).
class MlKitScanPriceService implements IScanPriceService {
  final ImagePicker _picker;
  final TextRecognizer _textRecognizer;

  MlKitScanPriceService({
    ImagePicker? picker,
    TextRecognizer? textRecognizer,
  })  : _picker = picker ?? ImagePicker(),
        _textRecognizer = textRecognizer ??
            TextRecognizer(script: TextRecognitionScript.latin);

  @override
  Future<ScanServiceResult> captureAndParse({
    ImageSource source = ImageSource.camera,
  }) async {
    try {
      // Batasi resolusi ke 1920px & kualitas 85% untuk mencegah OOM & mempercepat OCR.
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFile == null) {
        return ScanServiceResult.cancelled();
      }

      final rawText = await recognizeTextFromFile(File(pickedFile.path));
      if (rawText.trim().isEmpty) {
        return ScanServiceResult.failure(
          'Tidak ada teks yang terbaca dari foto. Pastikan label harga terlihat jelas dan tidak buram.',
        );
      }

      final parsed = ScanPriceParser.parseScan(rawText);
      if (!parsed.hasAnyData) {
        return ScanServiceResult.failure(
          'Teks berhasil dibaca, tetapi tidak ditemukan pola nama produk atau harga yang valid (Rp 50rb - 150jt).',
        );
      }

      return ScanServiceResult.success(parsed);
    } catch (e) {
      return ScanServiceResult.failure(
        'Gagal memproses gambar di perangkat. Layanan OCR mungkin belum siap atau perangkat tidak mendukung.',
      );
    }
  }

  @override
  Future<String> recognizeTextFromFile(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final RecognizedText recognizedText =
        await _textRecognizer.processImage(inputImage);
    return recognizedText.text;
  }

  @override
  Future<void> dispose() async {
    await _textRecognizer.close();
  }
}
