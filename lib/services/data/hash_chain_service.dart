import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Tamper-evident hash chain untuk riwayat analisis harga.
///
/// Format (PLAN.md D12): `SHA256("$index|$timestamp|${json(data)}|$prevHash")`
/// dengan `prevHash = "GENESIS"` untuk blok pertama. Ini mengadopsi *konsep*
/// blockchain (rantai hash), bukan blockchain desentralisasi.
abstract final class HashChainService {
  static const genesisPrevHash = 'GENESIS';

  /// Hitung hash satu blok.
  static String computeHash({
    required int index,
    required String timestampIso,
    required String dataJson,
    required String prevHash,
  }) {
    final raw = '$index|$timestampIso|$dataJson|$prevHash';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  /// Bangun JSON kanonis untuk sebuah hasil analisis (field terurut).
  static String canonicalDataJson({
    required String mode,
    required String query,
    required int inputPrice,
    required double score,
    required String verdict,
  }) =>
      jsonEncode({
        'input_price': inputPrice,
        'mode': mode,
        'query': query,
        'score': score,
        'verdict': verdict,
      });

  /// Verifikasi seluruh rantai (urut id menaik).
  ///
  /// Return daftar [HashVerificationResult] per blok: ok bila hash cocok DAN
  /// prevHash cocok dengan hash blok sebelumnya (atau GENESIS untuk pertama).
  static List<HashVerificationResult> verifyChain(List<HashBlock> blocks) {
    final results = <HashVerificationResult>[];
    var prevHash = genesisPrevHash;
    for (final block in blocks) {
      final expected = computeHash(
        index: block.id,
        timestampIso: block.timestampIso,
        dataJson: block.dataJson,
        prevHash: block.prevHash,
      );
      // Blok tidak valid bila datanya diubah (hash mismatch) ATAU rantainya
      // putus (prevHash tidak cocok dengan hash blok sebelumnya) — efeknya
      // menular ke semua blok sesudahnya.
      final ok = block.hash == expected && block.prevHash == prevHash;
      results.add(HashVerificationResult(block: block, ok: ok));
      prevHash = block.hash;
    }
    return results;
  }
}

/// Data minimal satu blok untuk verifikasi (agnostik Drift).
class HashBlock {
  const HashBlock({
    required this.id,
    required this.timestampIso,
    required this.dataJson,
    required this.prevHash,
    required this.hash,
  });

  final int id;
  final String timestampIso;
  final String dataJson;
  final String prevHash;
  final String hash;
}

class HashVerificationResult {
  const HashVerificationResult({required this.block, required this.ok});

  final HashBlock block;
  final bool ok;
}
