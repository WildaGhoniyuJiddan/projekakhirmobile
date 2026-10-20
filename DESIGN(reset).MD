# DESIGN.MD — Monex Financial UI Design System (Flutter / Dart)

Dokumen ini adalah acuan tunggal (*Single Source of Truth*) untuk **Visual Style**, **Design Tokens**, dan **Reusable Widget Architecture** pada aplikasi Android (Flutter). Seluruh halaman dan fitur baru wajib mengikuti spesifikasi warna, tipografi, *spacing*, dan komponen di dalam dokumen ini.

---

## 1. Identitas Visual & Prinsip Desain

* **Tema Utama:** *Deep Dark Fintech* — memadukan latar belakang gelap pekat (`#0C0F17`) dengan permukaan kartu berlapis (`#1B202C` & `#262C3C`) serta aksen kontras tinggi **Neon Lime (`#ACEF34`)**.
* **Karakter Sudut (Border Radius):** Menggunakan sudut ekstra membulat (*squircle/pill-friendly*). Kartu standar menggunakan radius `20.0`, kontainer numpad/modal menggunakan `24.0`–`28.0`, dan tombol/tab menggunakan `StadiumBorder` (`999.0`).
* **Garis Tepi (Borders):** Setiap kartu permukaan (*surface card*) memiliki *border* tipis `1.0px` berwarna putih transparan (`rgba(255, 255, 255, 0.06)` hingga `0.10`) untuk memberi efek kedalaman tanpa bayangan berat.
* **Pencahayaan (Glow & Blur):** Elemen aksi utama (*Primary CTA* & tombol tengah navigasi) memiliki *drop shadow* berpendar hijau neon (`limeGlowShadow`). Navigasi bawah dan *toast* menggunakan efek `BackdropFilter` (*glassmorphism* `blur: 12`).

---

## 2. Dependensi Utama (`pubspec.yaml`)

Pastikan paket berikut terpasang di project Flutter:

```yaml
dependencies:
  flutter:
    sdk: flutter
  google_fonts: ^6.2.1
  lucide_icons: ^0.257.0
```

---

## 3. Token Warna, Gradien & Bayangan

### 3.1. Tabel Referensi Cepat Token Warna

| Token | Hex / RGBA | Penggunaan Utama |
| :--- | :--- | :--- |
| `canvas` | `#070A10` | Latar belakang paling dasar / *splash* |
| `appBg` | `#0C0F17` | `scaffoldBackgroundColor` utama aplikasi |
| `surface` | `#1B202C` | Warna dasar semua *Card*, *List Tile*, dan *Bottom Nav* |
| `surfaceHover` | `#232938` | Efek *ripple* / *highlight* saat kartu ditekan |
| `surfaceElevated` | `#262C3C` | Tombol bundar sekunder, *chip*, tombol *numpad*, *tab* aktif |
| `borderSubtle` | `rgba(255,255,255,0.06)` | *Border* `1px` pada kartu & pemisah menu (*divider*) |
| `borderLight` | `rgba(255,255,255,0.10)` | *Border* *avatar*, *chip* luar, atau *badge* |
| `lime` | `#ACEF34` | Warna aksen utama, tombol CTA, indikator positif, *active icon* |
| `limeBright` | `#B8FF3B` | Warna *pressed/hover* pada tombol `lime` |
| `limeMuted` | `rgba(172,239,52,0.14)` | Efek *splash* atau latar *badge* positif |
| `danger` | `#F43F5E` | Indikator negatif, *overspent*, *error*, grafik turun |
| `dangerMuted` | `rgba(244,63,94,0.15)` | Latar *badge* peringatan / *error* |
| `chartPurple` | `#A855F7` | Bar indikator kategori sekunder (ungu) |
| `chartSky` | `#38BDF8` | Bar indikator kategori tersier (biru muda) |
| `chartTrack` | `#1E293B` | Latar belakang *progress bar* (`slate-800`) |
| `textPrimary` | `#F8FAFC` | Judul, angka saldo, nominal transaksi (`slate-50`) |
| `textSecondary` | `#94A3B8` | Label, sub-judul, *timestamp*, ikon non-aktif (`slate-400`) |
| `textMuted` | `#64748B` | Label sumbu grafik, *chevron* menu (`slate-500`) |
| `textDark` | `#020617` | Teks & ikon di atas latar belakang `lime` / Kartu VISA (`slate-950`) |

---

## 4. Implementasi Kode Tema (`lib/core/theme/monex_theme.dart`)

Gunakan file ini sebagai fondasi `ThemeData` dan *styling* dekorasi di seluruh aplikasi:

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class MonexColors {
  MonexColors._();

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
}

class MonexSpacing {
  MonexSpacing._();

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

class MonexDecorations {
  MonexDecorations._();

  /// Radial Gradient Kartu Debit / Kartu Utama (circle at 18% 20%)
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

  /// Glow Hijau Neon untuk Tombol Utama & FAB
  static List<BoxShadow> get limeGlowShadow => [
        const BoxShadow(
          color: Color.fromRGBO(172, 239, 52, 0.45),
          blurRadius: 24,
          spreadRadius: -4,
          offset: Offset(0, 8),
        ),
      ];

  /// Soft Shadow untuk Kartu Highlight
  static List<BoxShadow> get cardSoftShadow => [
        const BoxShadow(
          color: Color.fromRGBO(0, 0, 0, 0.50),
          blurRadius: 30,
          spreadRadius: -10,
          offset: Offset(0, 10),
        ),
      ];

  /// Dekorasi Standar Surface Card
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

  /// Dekorasi Kartu Gradien Neon
  static BoxDecoration visaCard({double radius = MonexSpacing.radiusCard}) {
    return BoxDecoration(
      gradient: visaCardGradient,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: cardSoftShadow,
    );
  }
}

class MonexTheme {
  MonexTheme._();

  static ThemeData get darkTheme {
    final baseTextTheme = GoogleFonts.plusJakartaSansTextTheme(
      ThemeData.dark().textTheme,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: MonexColors.appBg,
      canvasColor: MonexColors.canvas,
      primaryColor: MonexColors.lime,
      dividerColor: MonexColors.borderSubtle,
      colorScheme: const ColorScheme.dark(
        primary: MonexColors.lime,
        onPrimary: MonexColors.textDark,
        secondary: MonexColors.limeBright,
        surface: MonexColors.surface,
        onSurface: MonexColors.textPrimary,
        error: MonexColors.danger,
      ),
      textTheme: baseTextTheme.copyWith(
        // Angka Saldo Besar & Display Nominal ($6,324.49)
        displaySmall: baseTextTheme.displaySmall?.copyWith(
          fontSize: 30,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          color: MonexColors.textPrimary,
        ),
        // Judul Halaman Utama (Home, Analytics, Crypto, Settings)
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          color: MonexColors.textPrimary,
        ),
        // Nominal Kartu Sekunder ($8,567 / $82 567,6)
        titleMedium: baseTextTheme.titleMedium?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: MonexColors.textPrimary,
        ),
        // Judul Seksi & Nama Item List (Recent Transfers, Bolt Food)
        titleSmall: baseTextTheme.titleSmall?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: MonexColors.textPrimary,
        ),
        // Teks Isi & Menu
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: MonexColors.textSecondary,
        ),
        // Label Kecil, Timestamp, & Caption (11px)
        labelSmall: baseTextTheme.labelSmall?.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: MonexColors.textSecondary,
        ),
      ),
    );
  }
}
```

---

## 5. Katalog Komponen UI (`lib/core/widgets/monex_widgets.dart`)

Seluruh *widget* di bawah ini dirancang *reusable* dan *stateless/modular* sehingga dapat langsung dipakai untuk fitur apapun di dalam project:

```dart
import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/monex_theme.dart';

/// ============================================================================
/// 5.1. SURFACE CARD (Kontainer Dasar Semua Elemen)
/// ============================================================================
class MonexSurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? borderColor;

  const MonexSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(MonexSpacing.cardPadding),
    this.borderRadius = MonexSpacing.radiusCard,
    this.onTap,
    this.backgroundColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        highlightColor: MonexColors.surfaceHover,
        splashColor: MonexColors.limeMuted,
        child: Ink(
          padding: padding,
          decoration: MonexDecorations.surfaceCard(
            radius: borderRadius,
            color: backgroundColor,
            borderColor: borderColor,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// ============================================================================
/// 5.2. HEADER BAR LAYAR (Judul + Tombol Ikon Bundar)
/// ============================================================================
class MonexAppBar extends StatelessWidget {
  final String title;
  final IconData? leadingIcon;
  final VoidCallback? onLeadingTap;
  final IconData? trailingIcon;
  final VoidCallback? onTrailingTap;
  final bool centerTitle;

  const MonexAppBar({
    super.key,
    required this.title,
    this.leadingIcon,
    this.onLeadingTap,
    this.trailingIcon,
    this.onTrailingTap,
    this.centerTitle = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (leadingIcon != null)
          _CircleIconButton(icon: leadingIcon!, onTap: onLeadingTap)
        else if (centerTitle)
          const SizedBox(width: 34),
        Text(
          title,
          style: centerTitle
              ? Theme.of(context).textTheme.titleSmall
              : Theme.of(context).textTheme.titleLarge,
        ),
        if (trailingIcon != null)
          _CircleIconButton(icon: trailingIcon!, onTap: onTrailingTap)
        else if (centerTitle)
          const SizedBox(width: 34),
      ],
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _CircleIconButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        width: 34,
        height: 34,
        decoration: const BoxDecoration(
          color: MonexColors.surface,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 17, color: MonexColors.textPrimary),
      ),
    );
  }
}

/// ============================================================================
/// 5.3. TOMBOL AKSI BUNDAR (Withdraw, Top up, Exchange, Trade, Send, Receive)
/// ============================================================================
class MonexActionCircleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isHighlighted;

  const MonexActionCircleButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isHighlighted ? MonexColors.lime : MonexColors.surfaceElevated,
              shape: BoxShape.circle,
              boxShadow: isHighlighted ? MonexDecorations.limeGlowShadow : null,
            ),
            child: Icon(
              icon,
              size: 18,
              color: isHighlighted ? MonexColors.textDark : MonexColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: MonexColors.textPrimary.withOpacity(0.85),
                ),
          ),
        ],
      ),
    );
  }
}

/// ============================================================================
/// 5.4. TOMBOL UTAMA LIME GLOW (Full-Width Pill CTA)
/// ============================================================================
class MonexPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const MonexPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(MonexSpacing.radiusPill),
        boxShadow: MonexDecorations.limeGlowShadow,
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: MonexColors.lime,
          foregroundColor: MonexColors.textDark,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

/// ============================================================================
/// 5.5. SEGMENTED PILL CONTROL (Filter Periode: Monthly / Weekly / Daily)
/// ============================================================================
class MonexSegmentedControl extends StatelessWidget {
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const MonexSegmentedControl({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: MonexColors.surface,
        borderRadius: BorderRadius.circular(MonexSpacing.radiusPill),
        border: Border.all(color: MonexColors.borderSubtle),
      ),
      child: Row(
        children: List.generate(tabs.length, (index) {
          final isSelected = index == selectedIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected ? MonexColors.surfaceElevated : Colors.transparent,
                  borderRadius: BorderRadius.circular(MonexSpacing.radiusPill),
                ),
                alignment: Alignment.center,
                child: Text(
                  tabs[index],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? MonexColors.textPrimary : MonexColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// ============================================================================
/// 5.6. ITEM RIWAYAT TRANSAKSI / ASET (List Tile Card)
/// ============================================================================
class MonexTransactionTile extends StatelessWidget {
  final Widget leadingAvatar;
  final String title;
  final String subtitle;
  final String trailingPrimary;
  final String trailingSecondary;
  final Color? trailingSecondaryColor;
  final VoidCallback? onTap;

  const MonexTransactionTile({
    super.key,
    required this.leadingAvatar,
    required this.title,
    required this.subtitle,
    required this.trailingPrimary,
    required this.trailingSecondary,
    this.trailingSecondaryColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MonexSurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          SizedBox(width: 38, height: 38, child: leadingAvatar),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                trailingPrimary,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                trailingSecondary,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: trailingSecondaryColor ?? MonexColors.textSecondary,
                      fontWeight: trailingSecondaryColor != null
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// ============================================================================
/// 5.7. SPLINE AREA CHART (Grafik Area Melengkung + Gradien Transparan)
/// ============================================================================
class MonexSplineChart extends StatelessWidget {
  final List<double> normalizedPoints; // Nilai antara 0.0 s/d 1.0
  final Color color;
  final double height;

  const MonexSplineChart({
    super.key,
    required this.normalizedPoints,
    this.color = MonexColors.lime,
    this.height = 95,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SplineAreaPainter(
          points: normalizedPoints,
          lineColor: color,
        ),
      ),
    );
  }
}

class _SplineAreaPainter extends CustomPainter {
  final List<double> points;
  final Color lineColor;

  _SplineAreaPainter({required this.points, required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final path = Path();
    final stepX = size.width / (points.length - 1);

    Offset getCoord(int i) => Offset(
          i * stepX,
          size.height - (points[i].clamp(0.0, 1.0) * (size.height * 0.85)),
        );

    final first = getCoord(0);
    path.moveTo(first.dx, first.dy);

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = getCoord(i);
      final p1 = getCoord(i + 1);
      final controlX = (p0.dx + p1.dx) / 2;
      path.cubicTo(controlX, p0.dy, controlX, p1.dy, p1.dx, p1.dy);
    }

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          lineColor.withOpacity(0.45),
          lineColor.withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _SplineAreaPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.lineColor != lineColor;
}

/// ============================================================================
/// 5.8. MINI BAR & PROGRESS INDICATORS (Untuk Kartu Statistik / Analytics)
/// ============================================================================
class MonexMiniVerticalBars extends StatelessWidget {
  final List<double> heights; // Nilai antara 0.2 s/d 1.0

  const MonexMiniVerticalBars({super.key, required this.heights});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: heights.map((factor) {
          final isTall = factor >= 0.6;
          return Container(
            width: 8,
            height: 44 * factor.clamp(0.15, 1.0),
            decoration: BoxDecoration(
              color: isTall ? MonexColors.barActive : MonexColors.barInactive,
              borderRadius: BorderRadius.circular(99),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class MonexProgressBar extends StatelessWidget {
  final List<double> fractions;
  final List<Color> colors;

  const MonexProgressBar({
    super.key,
    required this.fractions,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 8,
      width: double.infinity,
      decoration: BoxDecoration(
        color: MonexColors.chartTrack,
        borderRadius: BorderRadius.circular(99),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          return Row(
            children: List.generate(fractions.length, (i) {
              return Container(
                width: constraints.maxWidth * fractions[i],
                height: 8,
                color: colors[i],
              );
            }),
          );
        },
      ),
    );
  }
}

/// ============================================================================
/// 5.9. RECIPIENT AVATAR PICKER & NUMPAD GRID (Untuk Layar Send Money / Input)
/// ============================================================================
class MonexRecipientAvatar extends StatelessWidget {
  final String name;
  final ImageProvider image;
  final bool isSelected;
  final VoidCallback onTap;

  const MonexRecipientAvatar({
    super.key,
    required this.name,
    required this.image,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? MonexColors.lime : Colors.transparent,
                width: 2,
              ),
            ),
            child: CircleAvatar(
              radius: 21,
              backgroundImage: image,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            name,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected ? MonexColors.textPrimary : MonexColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class MonexNumpadGrid extends StatelessWidget {
  final ValueChanged<String> onKeyTap;
  final VoidCallback onBackspace;

  const MonexNumpadGrid({
    super.key,
    required this.onKeyTap,
    required this.onBackspace,
  });

  @override
  Widget build(BuildContext context) {
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0', 'back'];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: keys.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        mainAxisExtent: 42,
      ),
      itemBuilder: (context, index) {
        final key = keys[index];
        final isBackspace = key == 'back';

        return Material(
          color: MonexColors.surfaceElevated,
          borderRadius: BorderRadius.circular(MonexSpacing.radiusPill),
          child: InkWell(
            borderRadius: BorderRadius.circular(MonexSpacing.radiusPill),
            onTap: () => isBackspace ? onBackspace() : onKeyTap(key),
            child: Center(
              child: isBackspace
                  ? const Icon(Icons.backspace_outlined, size: 17, color: MonexColors.textPrimary)
                  : Text(
                      key,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: MonexColors.textPrimary,
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// ============================================================================
/// 5.10. FLOATING BOTTOM NAVIGATION BAR (Blur Glassmorphism + Center Glow FAB)
/// ============================================================================
class MonexBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onCenterPlusTap;

  const MonexBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.onCenterPlusTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(MonexSpacing.radiusCard),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: MonexColors.surface.withOpacity(0.90),
            borderRadius: BorderRadius.circular(MonexSpacing.radiusCard),
            border: Border.all(color: MonexColors.borderSubtle),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _BottomNavItem(
                icon: Icons.home_outlined,
                label: 'Home',
                isActive: currentIndex == 0,
                onTap: () => onTap(0),
              ),
              _BottomNavItem(
                icon: Icons.bar_chart_rounded,
                label: 'Analytics',
                isActive: currentIndex == 1,
                onTap: () => onTap(1),
              ),
              GestureDetector(
                onTap: onCenterPlusTap,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: MonexColors.lime,
                    shape: BoxShape.circle,
                    boxShadow: MonexDecorations.limeGlowShadow,
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: MonexColors.textDark,
                    size: 24,
                  ),
                ),
              ),
              _BottomNavItem(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Crypto',
                isActive: currentIndex == 2,
                onTap: () => onTap(2),
              ),
              _BottomNavItem(
                icon: Icons.settings_outlined,
                label: 'Settings',
                isActive: currentIndex == 3,
                onTap: () => onTap(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive ? MonexColors.lime : MonexColors.textSecondary,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? MonexColors.textPrimary : MonexColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ============================================================================
/// 5.11. TOAST NOTIFICATION HELPER (Floating Glassmorphic SnackBar)
/// ============================================================================
void showMonexToast(BuildContext context, String message, {bool isError = false}) {
  final accentColor = isError ? MonexColors.danger : MonexColors.lime;

  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      duration: const Duration(milliseconds: 2400),
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: MonexColors.surfaceElevated.withOpacity(0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accentColor, width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: accentColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: MonexColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
```

---

## 6. Spesifikasi Pola Halaman (Screen Blueprints)

Saat mengadaptasi komponen di atas ke fitur aplikasi kamu, ikuti aturan tata letak (*layout rules*) per jenis layar berikut:

### 6.1. Pola Layar Utama / Dashboard (Home)
1. **Top Bar:** `MonexAppBar` dengan judul di kiri dan tombol lonceng notifikasi bundar di kanan.
2. **Hero Card (Expandable/Flippable Card):**
   * **State Collapsed:** Bar tipis tinggi `24px` dengan `visaCardGradient`, *border radius* atas `18px`, dan *tab chevron* di bagian tengah bawah.
   * **State Front:** Tinggi `156px`, latar `visaCardGradient`, menampilkan status *tier* di kiri atas, digit akhir di kiri bawah, dan logo jaringan/aplikasi miring tebal (`FontWeight.w900`) di kanan bawah.
   * **State Back:** Tinggi `156px`, menampilkan detail nomor/kode dengan tombol salin (`Icons.copy_rounded`).
3. **Summary Balance Card:** `MonexSurfaceCard` berisi label kecil (`12px`), nominal utama (`30px bold`), *badge* persentase/pertumbuhan (`12px lime`), diikuti baris 3 tombol `MonexActionCircleButton`.
4. **Recent List Section:** Header seksi dengan tombol `"View All"` di kanan, diikuti daftar `MonexTransactionTile` dengan jarak antar item `8px`–`10px`.

### 6.2. Pola Layar Analitik & Laporan (Analytics)
1. **Filter Periode:** `MonexSegmentedControl` di bawah *header* untuk berpindah rentang waktu.
2. **Primary Chart Card:** `MonexSurfaceCard` menampilkan nilai metrik utama, *delta* kenaikan/penurunan (`▲` atau `▼`), dan `MonexSplineChart` diikuti baris label sumbu X dengan garis batas atas `borderSubtle`.
3. **2-Column Breakdown Grid:** Menggunakan `Row` dengan 2 `Expanded` (`gap: 12px`) yang masing-masing berisi `MonexSurfaceCard` untuk perbandingan vertikal (`MonexMiniVerticalBars`) dan proporsi kategori (`MonexProgressBar`).
4. **Status Footer Card:** Kartu ringkas penuh lebar untuk menampilkan status kuota/anggaran (`● Overspent` dengan warna `danger` atau `● Positive` dengan warna `lime`).

### 6.3. Pola Layar Input Nominal / Transaksi (Send Money)
1. **Carousel Subjek/Penerima:** `SingleChildScrollView` horizontal berisi tombol `"Add New"` bundar di awal dan deretan `MonexRecipientAvatar`.
2. **Numpad Container Card:** Satu `MonexSurfaceCard` besar (`borderRadius: 24`) yang merangkum:
   * *Pill selector* sumber dana/kategori di bagian atas tengah (`bg: surfaceElevated`).
   * Tampilan angka nominal dinamis berukuran besar (`30px bold`) dengan kursor garis berkedip berwarna `lime` (`width: 2, height: 24`).
   * Teks status/validasi di bawah nominal (berubah menjadi merah `danger` jika melebihi batas/saldo).
   * Baris 5 *chip* nominal cepat (`$50`, `$100`, dst.) menggunakan bentuk *pill* (`surfaceElevated`, berubah menjadi `lime` saat ditekan).
   * `MonexNumpadGrid` (3 kolom x 4 baris) dan ditutup dengan `MonexPrimaryButton` di bagian paling bawah kartu.

### 6.4. Pola Layar Pengaturan & Profil (Settings)
1. **Centered Profile Header:** Foto profil bundar (`64x64`) dengan `borderLight`, nama pengguna (`18px bold`), dan *handle/username* (`12px textSecondary`) rata tengah.
2. **2-Column Feature Highlight Cards:** 2 kartu `MonexSurfaceCard` berdampingan (`minHeight: 104px`) dengan ikon berlatar `lime` di sudut atas dan judul fitur di sudut bawah.
3. **Grouped Menu List:** Satu `MonexSurfaceCard` (`padding: EdgeInsets.zero`) yang membungkus beberapa baris menu (`ListTile` padat) yang dipisahkan oleh `Divider(height: 1, color: MonexColors.borderSubtle)`.

---

## 7. Checklist Konsistensi Desain (Untuk Developer / AI Assistant)

Setiap kali membuat halaman atau *widget* baru di project ini, pastikan:
- [ ] Latar belakang `Scaffold` selalu `MonexColors.appBg` (`#0C0F17`), **bukan** hitam murni (`#000000`) atau abu-abu bawaan Material.
- [ ] Semua kartu menggunakan `MonexSurfaceCard` (`#1B202C`) dengan *border* `1px` `MonexColors.borderSubtle`.
- [ ] Tidak menggunakan `elevation` bawaan Material pada kartu; gunakan kontras warna antara `appBg`, `surface`, dan `surfaceElevated`.
- [ ] Setiap teks di atas latar `MonexColors.lime` wajib menggunakan warna gelap `MonexColors.textDark` (`#020617`) agar kontras keterbacaan terjaga.
- [ ] Gunakan font **Plus Jakarta Sans** untuk seluruh teks dan angka.