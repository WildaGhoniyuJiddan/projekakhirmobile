import 'package:flutter/material.dart';

/// Design system "Monex" — Deep Dark Fintech.
///
/// Sumber acuan: `DESIGN(reset).MD` §3–4. Token di bawah disalin persis
/// dari dokumen; Plus Jakarta Sans di-*self-host* (bundled di
/// `assets/fonts/`) supaya tema konsisten tanpa fetch runtime.
///
/// Dark = implementasi literal dokumen. Light = inversi semantik dari
/// token yang sama (surface/appBg/teks), supaya toggle tema di Profil
/// tetap punya arti; aksen lime tetap sama di kedua mode.
abstract final class MonexColors {
  // Backgrounds
  static const Color canvas = Color(0xFF070A10);
  static const Color appBg = Color(0xFF0C0F17);

  // Surfaces & Borders
  static const Color surface = Color(0xFF1B202C);
  static const Color surfaceHover = Color(0xFF232938);
  static const Color surfaceElevated = Color(0xFF262C3C);
  static const Color borderSubtle = Color.fromRGBO(255, 255, 255, 0.06);
  static const Color borderLight = Color.fromRGBO(255, 255, 255, 0.10);

  // Primary Brand Accent (Neon Lime)
  static const Color lime = Color(0xFFACEF34);
  static const Color limeBright = Color(0xFFB8FF3B);
  static const Color limeMuted = Color.fromRGBO(172, 239, 52, 0.14);

  // Semantic & Secondary Accents
  static const Color danger = Color(0xFFF43F5E);
  static const Color dangerMuted = Color.fromRGBO(244, 63, 94, 0.15);
  static const Color chartPurple = Color(0xFFA855F7);
  static const Color chartSky = Color(0xFF38BDF8);
  static const Color chartTrack = Color(0xFF1E293B);
  static const Color barInactive = Color(0xFF475569);
  static const Color barActive = Color(0xFF64748B);

  // Typography
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
  static const Color textDark = Color(0xFF020617);

  /// Warna verdict — semantik app (hijau/amber/merah) digeser ke palet
  /// dark agar kontras di atas [surface] tetap terbaca.
  /// Warna TIDAK pernah berdiri sendiri: selalu berpasangan dengan label teks.
  static const Color verdictGood = Color(0xFF4ADE80);
  static const Color verdictFair = Color(0xFFFBBF24);
  static const Color verdictBad = Color(0xFFF87171);
}

/// Token spacing & radius (DESIGN(reset).MD §3.1).
abstract final class MonexSpacing {
  static const double screenPaddingH = 20.0;
  static const double screenPaddingV = 16.0;
  static const double cardPadding = 16.0;
  static const double cardPaddingCompact = 14.0;
  static const double gridGap = 12.0;
  static const double sectionGap = 18.0;

  static const double radiusSm = 12.0;
  static const double radiusMd = 16.0;
  static const double radiusCard = 20.0;
  static const double radiusSheet = 24.0;
  static const double radiusPill = 999.0;
}

/// Dekorasi: gradient, glow, dan standard surface card.
abstract final class MonexDecorations {
  /// Radial Gradient Kartu Utama (circle at 18% 20%).
  static const RadialGradient visaCardGradient = RadialGradient(
    center: Alignment(-0.64, -0.60),
    radius: 1.4,
    colors: [
      Color(0xFFF7FAE9), // 0%
      Color(0xFFDEF98E), // 45%
      Color(0xFF97F129), // 100%
    ],
    stops: [0.0, 0.45, 1.0],
  );

  /// Glow Hijau Neon untuk Tombol Utama & FAB.
  static List<BoxShadow> get limeGlowShadow => const [
        BoxShadow(
          color: Color.fromRGBO(172, 239, 52, 0.45),
          blurRadius: 24,
          spreadRadius: -4,
          offset: Offset(0, 8),
        ),
      ];

  /// Soft Shadow untuk Kartu Highlight.
  static List<BoxShadow> get cardSoftShadow => const [
        BoxShadow(
          color: Color.fromRGBO(0, 0, 0, 0.50),
          blurRadius: 30,
          spreadRadius: -10,
          offset: Offset(0, 10),
        ),
      ];

  /// Dekorasi Standar Surface Card.
  static BoxDecoration surfaceCard({
    double radius = MonexSpacing.radiusCard,
    Color? color,
    Color? borderColor,
  }) {
    return BoxDecoration(
      color: color ?? MonexColors.surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ?? MonexColors.borderSubtle,
        width: 1,
      ),
    );
  }

  /// Dekorasi Kartu Gradien Neon.
  static BoxDecoration visaCard({double radius = MonexSpacing.radiusCard}) {
    return BoxDecoration(
      gradient: visaCardGradient,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: cardSoftShadow,
    );
  }
}

/// Font family yang di-*self-host* (lihat `pubspec.yaml` → flutter.fonts).
const String kMonexFontFamily = 'PlusJakartaSans';

/// Palet per-mode: dark memakai token dokumen apa adanya; light memakai
/// inversi semantik dari token yang sama.
@immutable
class MonexPalette {
  const MonexPalette({
    required this.brightness,
    required this.appBg,
    required this.canvas,
    required this.surface,
    required this.surfaceHover,
    required this.surfaceElevated,
    required this.borderSubtle,
    required this.borderLight,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.danger,
    required this.dangerMuted,
    required this.chartTrack,
    required this.barInactive,
    required this.barActive,
  });

  final Brightness brightness;
  final Color appBg;
  final Color canvas;
  final Color surface;
  final Color surfaceHover;
  final Color surfaceElevated;
  final Color borderSubtle;
  final Color borderLight;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color danger;
  final Color dangerMuted;
  final Color chartTrack;
  final Color barInactive;
  final Color barActive;

  static const MonexPalette dark = MonexPalette(
    brightness: Brightness.dark,
    appBg: MonexColors.appBg,
    canvas: MonexColors.canvas,
    surface: MonexColors.surface,
    surfaceHover: MonexColors.surfaceHover,
    surfaceElevated: MonexColors.surfaceElevated,
    borderSubtle: MonexColors.borderSubtle,
    borderLight: MonexColors.borderLight,
    textPrimary: MonexColors.textPrimary,
    textSecondary: Color(0xFFCBD5E1),
    textMuted: Color(0xFF94A3B8),
    danger: MonexColors.danger,
    dangerMuted: MonexColors.dangerMuted,
    chartTrack: MonexColors.chartTrack,
    barInactive: MonexColors.barInactive,
    barActive: MonexColors.barActive,
  );

  static const MonexPalette light = MonexPalette(
    brightness: Brightness.light,
    appBg: Color(0xFFF4F6FA),
    canvas: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceHover: Color(0xFFF1F5F9),
    surfaceElevated: Color(0xFFE2E8F0),
    borderSubtle: Color.fromRGBO(15, 23, 42, 0.08),
    borderLight: Color.fromRGBO(15, 23, 42, 0.12),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF334155),
    textMuted: Color(0xFF64748B),
    danger: Color(0xFFE11D48),
    dangerMuted: Color.fromRGBO(225, 29, 72, 0.12),
    chartTrack: Color(0xFFE2E8F0),
    barInactive: Color(0xFFCBD5E1),
    barActive: Color(0xFF94A3B8),
  );
}

/// Theme aplikasi. Dark = implementasi literal DESIGN(reset).MD.
abstract final class MonexTheme {
  static ThemeData get darkTheme => _build(MonexPalette.dark);

  static ThemeData get lightTheme => _build(MonexPalette.light);

  static ThemeData _build(MonexPalette p) {
    final base = ThemeData(brightness: p.brightness, useMaterial3: true);
    final baseTextTheme = base.textTheme.apply(
      fontFamily: kMonexFontFamily,
      bodyColor: p.textPrimary,
      displayColor: p.textPrimary,
    );

    return base.copyWith(
      scaffoldBackgroundColor: p.appBg,
      cardColor: p.surface,
      canvasColor: p.canvas,
      primaryColor: MonexColors.lime,
      dividerColor: p.borderSubtle,
      colorScheme: ColorScheme(
        brightness: p.brightness,
        primary: MonexColors.lime,
        onPrimary: MonexColors.textDark,
        primaryContainer: p.surfaceElevated,
        onPrimaryContainer: p.textPrimary,
        secondary: MonexColors.limeBright,
        onSecondary: MonexColors.textDark,
        secondaryContainer: MonexColors.limeMuted,
        onSecondaryContainer: p.textPrimary,
        surface: p.surface,
        onSurface: p.textPrimary,
        surfaceContainerHighest: p.surfaceElevated,
        onSurfaceVariant: p.textSecondary,
        surfaceContainerLow: p.surfaceHover,
        surfaceContainer: p.surface,
        surfaceContainerHigh: p.surfaceElevated,
        error: p.danger,
        onError: MonexColors.textDark,
        errorContainer: p.dangerMuted,
        onErrorContainer: p.textPrimary,
        outline: p.borderLight,
        outlineVariant: p.borderSubtle,
        shadow: Colors.black,
        scrim: Colors.black,
        inverseSurface: p.surface,
        onInverseSurface: p.textPrimary,
        inversePrimary: MonexColors.lime,
      ),
      textTheme: baseTextTheme.copyWith(
        // Angka nominal besar & display.
        displaySmall: baseTextTheme.displaySmall?.copyWith(
          fontSize: 30,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          color: p.textPrimary,
        ),
        // Judul halaman utama.
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          color: p.textPrimary,
        ),
        // Nominal kartu sekunder.
        titleMedium: baseTextTheme.titleMedium?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: p.textPrimary,
        ),
        // Judul seksi & nama item list.
        titleSmall: baseTextTheme.titleSmall?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: p.textPrimary,
        ),
        // Teks isi & menu.
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: p.textSecondary,
        ),
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: p.textSecondary,
        ),
        bodySmall: baseTextTheme.bodySmall?.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: p.textMuted,
        ),
        // Label kecil, timestamp, caption.
        labelSmall: baseTextTheme.labelSmall?.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: p.textSecondary,
        ),
        labelLarge: baseTextTheme.labelLarge?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: p.textPrimary,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.appBg,
        foregroundColor: p.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: kMonexFontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          color: p.textPrimary,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: MonexColors.limeMuted,
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: selected ? MonexColors.lime : p.textSecondary,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: kMonexFontFamily,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? p.textPrimary : p.textSecondary,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        // Prefix icon default Flutter 48px + prefixText + padding = Row
        // melebihi 320px di layar sempit. Ketatkan constraint agar aman.
        prefixIconConstraints: const BoxConstraints(
          minWidth: 40,
          minHeight: 40,
        ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 40,
          minHeight: 40,
        ),
        hintStyle: TextStyle(color: p.textMuted, fontSize: 12),
        labelStyle: TextStyle(color: p.textSecondary, fontSize: 12),
        floatingLabelStyle: TextStyle(color: MonexColors.lime, fontSize: 12),
        prefixIconColor: p.textSecondary,
        suffixIconColor: p.textSecondary,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MonexSpacing.radiusMd),
          borderSide: BorderSide(color: p.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MonexSpacing.radiusMd),
          borderSide: const BorderSide(color: MonexColors.lime, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MonexSpacing.radiusMd),
          borderSide: BorderSide(color: p.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MonexSpacing.radiusMd),
          borderSide: BorderSide(color: p.danger, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: MonexColors.lime,
          foregroundColor: MonexColors.textDark,
          disabledBackgroundColor: p.surfaceElevated,
          disabledForegroundColor: p.textMuted,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontFamily: kMonexFontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.surfaceElevated,
          foregroundColor: p.textPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontFamily: kMonexFontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.textPrimary,
          side: BorderSide(color: p.borderLight),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontFamily: kMonexFontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: MonexColors.lime,
          textStyle: const TextStyle(
            fontFamily: kMonexFontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: p.surface,
          foregroundColor: p.textSecondary,
          selectedBackgroundColor: p.surfaceElevated,
          selectedForegroundColor: p.textPrimary,
          side: BorderSide(color: p.borderSubtle),
          textStyle: const TextStyle(
            fontFamily: kMonexFontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        selectedColor: MonexColors.limeMuted,
        side: BorderSide(color: p.borderSubtle),
        labelStyle: TextStyle(
          fontFamily: kMonexFontFamily,
          fontSize: 12,
          color: p.textSecondary,
        ),
        shape: const StadiumBorder(),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MonexSpacing.radiusSheet),
          side: BorderSide(color: p.borderSubtle),
        ),
        titleTextStyle: TextStyle(
          fontFamily: kMonexFontFamily,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: p.textPrimary,
        ),
        contentTextStyle: TextStyle(
          fontFamily: kMonexFontFamily,
          fontSize: 13,
          color: p.textSecondary,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.surfaceElevated,
        contentTextStyle: TextStyle(
          fontFamily: kMonexFontFamily,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: p.textPrimary,
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(MonexSpacing.radiusMd),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? MonexColors.textDark
              : p.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? MonexColors.lime
              : p.surfaceElevated;
        }),
        trackOutlineColor: WidgetStatePropertyAll(p.borderLight),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.textSecondary,
        textColor: p.textPrimary,
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: MonexColors.lime,
        inactiveTrackColor: MonexColors.chartTrack,
        thumbColor: MonexColors.lime,
        overlayColor: MonexColors.limeMuted,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: MonexColors.lime,
        linearTrackColor: p.chartTrack,
        circularTrackColor: p.chartTrack,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.surfaceElevated,
          borderRadius: BorderRadius.circular(MonexSpacing.radiusSm),
          border: Border.all(color: p.borderSubtle),
        ),
        textStyle: TextStyle(
          fontFamily: kMonexFontFamily,
          fontSize: 11,
          color: p.textPrimary,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: p.borderSubtle,
        thickness: 1,
        space: 1,
      ),
      splashFactory: InkSparkle.splashFactory,
    );
  }
}
