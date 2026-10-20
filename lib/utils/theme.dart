import 'package:flutter/material.dart';

import 'package:worthbang/core/theme/monex_theme.dart';

/// Tema aplikasi WorthBang — sekarang memakai design system "Monex"
/// (`DESIGN(reset).MD`).
///
/// API lama dipertahankan supaya seluruh call site tetap jalan; token
/// aslinya pindah ke [MonexColors].
///
/// Aturan aksesibilitas: warna verdict (hijau/amber/merah) TIDAK PERNAH
/// berdiri sendiri — selalu disertai label teks (lihat `VerdictBadge`).
abstract final class AppTheme {
  /// Hijau — harga "worth it" / sangat murah.
  static const Color verdictGood = MonexColors.verdictGood;

  /// Amber — harga wajar.
  static const Color verdictFair = MonexColors.verdictFair;

  /// Merah — kemahalan.
  static const Color verdictBad = MonexColors.verdictBad;

  static ThemeData get light => MonexTheme.lightTheme;

  static ThemeData get dark => MonexTheme.darkTheme;

  /// Warna verdict sesuai skor 0–100 (diselaraskan dengan backend scoring).
  static Color verdictColorFor(double score) {
    if (score >= 75) return verdictGood;
    if (score >= 50) return verdictFair;
    return verdictBad;
  }
}
