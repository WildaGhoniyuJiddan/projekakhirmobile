// Parser murni untuk fitur Pindai Harga: memilah teks mentah hasil OCR
// (Google ML Kit) menjadi nama produk + kandidat harga. Pure Dart, tanpa
// dependensi Flutter/plugin, supaya 100% logikanya bisa diuji unit test.
// Bukan LLM: hanya regex + heuristik deterministik.

class ScanParseResult {
  final String query;
  final List<int> priceCandidates;
  final int? defaultPrice;
  final String rawText;

  const ScanParseResult({
    required this.query,
    required this.priceCandidates,
    required this.defaultPrice,
    required this.rawText,
  });

  /// Bernilai true jika minimal salah satu dari nama atau harga berhasil diekstrak.
  bool get hasAnyData => query.isNotEmpty || priceCandidates.isNotEmpty;

  /// Bernilai true jika nama produk dan minimal satu harga siap dikirim ke analyze().
  bool get isReadyToAnalyze => query.isNotEmpty && defaultPrice != null;
}

class ScanPriceParser {
  // Rentang harga valid sesuai domain aplikasi (Rp 50.000 - Rp 150.000.000).
  static const int minValidPrice = 50000;
  static const int maxValidPrice = 150000000;

  // Kata kunci yang menandakan angka di baris tersebut BUKAN harga beli tunai utama.
  static final RegExp _secondaryPriceContextRegex = RegExp(
    r'\b(CICILAN|CCL|BLN|BULAN|HEMAT|DISKON|DISC|CASHBACK|CB|DP|UANG\s*MUKA|ANGSURAN|TEBUS)\b|/|\bX\b',
    caseSensitive: false,
  );

  // Kata kunci noise promosi & atribut toko yang harus dibuang dari kandidat nama produk.
  static final RegExp _retailStopwordsRegex = RegExp(
    r'\b(PROMO|HARGA\s*NORMAL|HARGA\s*SPESIAL|HARGA\s*MEMBER|MEMBER\s*PRICE|DISKON|CICILAN|CASHBACK|HEMAT|GARANSI\s*RESMI|GARANSI|FREE|BONUS|TERMURAH|BEST\s*SELLER|NEW\s*ARRIVAL|READY\s*STOCK|PCS|UNIT|PACK|GRAM|GR|KG|INC\s*PPN|BELUM\s*PPN)\b',
    caseSensitive: false,
  );

  // Pola tanggal cetak label (misal: 24/10/2026, 24-10-26, 2026-10-24).
  static final RegExp _datePatternRegex = RegExp(
    r'\b(\d{1,2}[/-]\d{1,2}[/-]\d{2,4}|\d{4}[/-]\d{1,2}[/-]\d{1,2})\b',
  );

  /// Fungsi utama untuk memilah teks mentah hasil OCR menjadi produk & kandidat harga.
  static ScanParseResult parseScan(String rawOcrText) {
    final normalizedRaw = rawOcrText.trim();
    if (normalizedRaw.isEmpty) {
      return const ScanParseResult(
        query: '',
        priceCandidates: [],
        defaultPrice: null,
        rawText: '',
      );
    }

    final priceExtraction = _extractPricesWithDefault(normalizedRaw);
    final productName = extractProductName(normalizedRaw);

    return ScanParseResult(
      query: productName,
      priceCandidates: priceExtraction.candidates,
      defaultPrice: priceExtraction.defaultPrice,
      rawText: normalizedRaw,
    );
  }

  /// Mengekstrak daftar kandidat harga valid [50rb - 150jt] dalam urutan baca.
  static List<int> extractPriceCandidates(String rawOcrText) {
    return _extractPricesWithDefault(rawOcrText).candidates;
  }

  /// Logika internal ekstraksi harga + penentuan smart default.
  static ({List<int> candidates, int? defaultPrice}) _extractPricesWithDefault(
    String rawOcrText,
  ) {
    final lines = rawOcrText
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final List<int> allCandidates = [];
    final List<int> primaryCandidates = []; // Harga bersih tanpa embel-embel cicilan/hemat.

    // Gabungkan baris yang hanya berisi "Rp" / "IDR" dengan baris tepat di bawahnya
    // (mengatasi kasus ML Kit memisahkan huruf "Rp" ukuran kecil dengan angka ukuran besar).
    final List<String> mergedLines = [];
    for (int i = 0; i < lines.length; i++) {
      final current = lines[i];
      if (RegExp(r'^(RP|IDR)\.?$', caseSensitive: false).hasMatch(current) &&
          i + 1 < lines.length) {
        mergedLines.add('$current ${lines[i + 1]}');
        i++; // Lompati baris berikutnya karena sudah digabung.
      } else {
        mergedLines.add(current);
      }
    }

    // Lapis 1: regex dengan jangkar Rp / IDR.
    final rpPriceRegex = RegExp(
      r'(?:RP|IDR)[\s.:,-]*([0-9OolI|SB][0-9OolI|SB.,\s]{3,16})',
      caseSensitive: false,
    );

    // Lapis 2 (fallback): angka berformat ribuan titik/koma khas harga Indonesia (tanpa Rp).
    // Contoh cocok: 1.250.000, 450.000, 12.500.000.
    final formattedNumberRegex = RegExp(
      r'\b([1-9OolI|SB][0-9OolI|SB]{0,2}(?:[.,][0-9OolI|SB]{3}){1,3})\b',
    );

    for (final line in mergedLines) {
      final bool isSecondaryLine = _secondaryPriceContextRegex.hasMatch(line);
      final List<int> linePrices = [];

      // Coba lapis 1 (dengan Rp/IDR).
      final rpMatches = rpPriceRegex.allMatches(line);
      for (final match in rpMatches) {
        final rawNum = match.group(1) ?? '';
        final parsed = _sanitizeAndParsePrice(rawNum);
        if (parsed != null) {
          linePrices.add(parsed);
        }
      }

      // Jika di baris ini tidak ada pola Rp, coba lapis 2 (format ribuan murni).
      if (linePrices.isEmpty) {
        final fallbackMatches = formattedNumberRegex.allMatches(line);
        for (final match in fallbackMatches) {
          final rawNum = match.group(1) ?? '';
          final parsed = _sanitizeAndParsePrice(rawNum);
          if (parsed != null) {
            linePrices.add(parsed);
          }
        }
      }

      for (final price in linePrices) {
        if (!allCandidates.contains(price)) {
          allCandidates.add(price);
        }
        if (!isSecondaryLine && !primaryCandidates.contains(price)) {
          primaryCandidates.add(price);
        }
      }
    }

    // Aturan smart default: pilih kandidat terakhir dari primaryCandidates
    // (karena harga promo biasanya di bawah harga coret). Jika semua harga
    // berada di baris sekunder, baru fallback ke kandidat terakhir dari allCandidates.
    int? smartDefault;
    if (primaryCandidates.isNotEmpty) {
      smartDefault = primaryCandidates.last;
    } else if (allCandidates.isNotEmpty) {
      smartDefault = allCandidates.last;
    }

    return (candidates: allCandidates, defaultPrice: smartDefault);
  }

  /// Sanitasi salah baca karakter OCR di dalam string angka & validasi rentang.
  static int? _sanitizeAndParsePrice(String rawNumericSegment) {
    String cleaned = rawNumericSegment.trim();

    // Potong akhiran desimal ",00" atau ".00" atau ",-" khas label Indonesia.
    cleaned = cleaned.replaceAll(RegExp(r'[.,]\s*(?:00|-|~)\s*$'), '');

    // Jika ada spasi diikuti angka pendek yang bukan kelipatan 3 digit
    // (misal kode di sebelah harga), potong.
    final tokens = cleaned.split(RegExp(r'\s+'));
    final validTokens = <String>[];
    for (final token in tokens) {
      if (validTokens.isEmpty) {
        validTokens.add(token);
      } else if (RegExp(r'^[0-9OolI|SB.,]+$').hasMatch(token)) {
        validTokens.add(token);
      } else {
        break;
      }
    }
    cleaned = validTokens.join('');

    // Sanitasi huruf yang sering salah dibaca sebagai angka oleh OCR.
    // Hanya di dalam blok angka, bukan di nama produk.
    cleaned = cleaned
        .replaceAll(RegExp(r'[Oo]'), '0')
        .replaceAll(RegExp(r'[lI|]'), '1')
        .replaceAll(RegExp(r'[Ss]'), '5')
        .replaceAll(RegExp(r'[B]'), '8');

    // Hapus semua pemisah ribuan (titik, koma, spasi).
    final digitsOnly = cleaned.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) return null;

    final value = int.tryParse(digitsOnly);
    if (value == null) return null;

    // Filter ke rentang harga proyek (50rb - 150jt).
    if (value < minValidPrice || value > maxValidPrice) {
      return null;
    }

    return value;
  }

  /// Mengekstrak dan menormalisasi nama produk dari teks OCR.
  static String extractProductName(String rawOcrText) {
    final lines = rawOcrText
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final List<String> candidateLines = [];

    for (final line in lines) {
      // 1. Buang baris yang jelas merupakan baris harga utama atau hanya simbol mata uang.
      if (RegExp(r'^(RP|IDR)\b', caseSensitive: false).hasMatch(line)) {
        continue;
      }
      if (RegExp(r'(?:RP|IDR)\s*[0-9OolI|SB.,]{4,}', caseSensitive: false)
          .hasMatch(line)) {
        continue;
      }

      // 2. Buang baris cicilan / diskon / hemat yang mengandung angka.
      if (_secondaryPriceContextRegex.hasMatch(line) &&
          RegExp(r'\d{2,}').hasMatch(line)) {
        continue;
      }

      // 3. Bersihkan tanggal, label SKU/kode, dan stopwords ritel dari dalam baris.
      String cleanedLine = line
          .replaceAll(_datePatternRegex, ' ')
          .replaceAll(
            RegExp(r'\b(SKU|KODE|ART|BARCODE|PLU|REF)\s*[:#-]?\s*[A-Z0-9-]+\b',
                caseSensitive: false),
            ' ',
          )
          .replaceAll(_retailStopwordsRegex, ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      // Bersihkan simbol pemisah di awal/akhir kalimat.
      cleanedLine =
          cleanedLine.replaceAll(RegExp(r'^[^a-zA-Z0-9]+|[^a-zA-Z0-9]+$'), '');

      if (cleanedLine.length < 4) continue;

      // 4. Hitung rasio huruf vs angka untuk membuang nomor barcode / SKU murni
      // (misal: 8992761134021).
      final int letterCount =
          RegExp(r'[a-zA-Z]').allMatches(cleanedLine).length;
      final int digitCount = RegExp(r'[0-9]').allMatches(cleanedLine).length;
      final int totalAlphaNum = letterCount + digitCount;

      if (totalAlphaNum == 0 || letterCount < 2) continue;

      // Jika lebih dari 60% karakter alfanumerik adalah angka dan tidak ada spasi kata,
      // besar kemungkinan itu nomor seri/barcode/harga tanpa Rp, bukan nama produk.
      final double digitRatio = digitCount / totalAlphaNum;
      if (digitRatio > 0.60 && !cleanedLine.contains(' ')) continue;

      // Buang jika baris murni angka ribuan (misal: "2.450.000").
      if (RegExp(r'^[0-9.,\s]+$').hasMatch(cleanedLine)) continue;

      candidateLines.add(cleanedLine);
    }

    if (candidateLines.isEmpty) return '';

    // Gabungkan maksimal 2 baris kandidat teratas agar merek (baris 1) +
    // tipe (baris 2) menyatu. Contoh: "SAMSUNG" + "SSD 980 PRO 1TB NVME".
    if (candidateLines.length >= 2 &&
        candidateLines[0].length <= 28 &&
        (candidateLines[0].length + candidateLines[1].length) <= 65) {
      return '${candidateLines[0]} ${candidateLines[1]}';
    }

    return candidateLines.first;
  }
}
