import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/monex_theme.dart';

// ============================================================================
// 5.1. SURFACE CARD — kartu dasar dengan border halus
// ============================================================================

/// Kartu permukaan standar Monex: radius 20, border 1px `borderSubtle`,
/// fill `surface`. [onTap] membuat kartu bisa ditekan (ink ripple).
class MonexSurfaceCard extends StatelessWidget {
  const MonexSurfaceCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(MonexSpacing.cardPadding),
    this.radius = MonexSpacing.radiusCard,
    this.color,
    this.borderColor,
    this.boxShadow,
    this.gradient,
    this.margin,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final Color? borderColor;
  final List<BoxShadow>? boxShadow;
  final Gradient? gradient;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: gradient == null ? (color ?? MonexColors.surface) : null,
      gradient: gradient,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ?? MonexColors.borderSubtle,
        width: 1,
      ),
      boxShadow: boxShadow,
    );

    final content = Padding(padding: padding, child: child);
    final card = onTap == null
        ? DecoratedBox(decoration: decoration, child: content)
        : Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(radius),
            clipBehavior: Clip.antiAlias,
            child: Ink(
              decoration: decoration,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(radius),
                child: content,
              ),
            ),
          );
    if (margin == null) return card;
    return Padding(padding: margin!, child: card);
  }
}

/// Kartu dengan gradien lime radial (kartu utama / hero).
class MonexGradientCard extends StatelessWidget {
  const MonexGradientCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(MonexSpacing.cardPadding),
    this.radius = MonexSpacing.radiusCard,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: MonexDecorations.visaCard(radius: radius),
        child: onTap == null
            ? content
            : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

// ============================================================================
// 5.2. APP BAR — judul + tombol aksi lingkaran
// ============================================================================

/// App bar Monex: judul rata-kiri, aksi melingkar (surfaceElevated).
///
/// [leadingIcon]/[actions] opsional agar pemanggil bebas; [showBack] memakai
/// `Navigator.maybePop` sehingga tetap aman di layar yang bukan route pushed.
class MonexAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MonexAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leadingIcon,
    this.onLeadingTap,
    this.showBack = false,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final IconData? leadingIcon;
  final VoidCallback? onLeadingTap;
  final bool showBack;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(66);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppBar(
      backgroundColor: theme.scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: MonexSpacing.screenPaddingH,
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          if (showBack || leadingIcon != null) ...[
            _CircleIconButton(
              icon: leadingIcon ?? Icons.arrow_back_ios_new_rounded,
              onTap: onLeadingTap ??
                  () => Navigator.of(context).maybePop(),
              size: 38,
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      actions: [
        ...actions,
        const SizedBox(width: MonexSpacing.screenPaddingH),
      ],
    );
  }
}

/// Tombol aksi berbentuk lingkaran di app bar.
class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    this.size = 40,
    this.tooltip,
    this.background,
    this.foreground,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final String? tooltip;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final button = Material(
      color: background ?? theme.colorScheme.surfaceContainerHighest,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: size * 0.45,
            color: foreground ?? theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// Tombol aksi lingkaran yang bisa dipakai di luar app bar.
class MonexCircleIconButton extends StatelessWidget {
  const MonexCircleIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 40,
    this.tooltip,
    this.background,
    this.foreground,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final String? tooltip;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) => _CircleIconButton(
        icon: icon,
        onTap: onTap,
        size: size,
        tooltip: tooltip,
        background: background,
        foreground: foreground,
      );
}

// ============================================================================
// 5.3. TOMBOL
// ============================================================================

/// Tombol utama Monex: lime solid, teks gelap, glow neon.
class MonexPrimaryButton extends StatelessWidget {
  const MonexPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expanded = true,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: MonexColors.lime,
        foregroundColor: MonexColors.textDark,
        disabledBackgroundColor: MonexColors.lime.withValues(alpha: 0.35),
        disabledForegroundColor: MonexColors.textDark.withValues(alpha: 0.6),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontFamily: kMonexFontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: loading
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: MonexColors.textDark,
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
    );

    if (!expanded) return button;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(MonexSpacing.radiusPill),
        boxShadow: onPressed != null && !loading
            ? MonexDecorations.limeGlowShadow
            : null,
      ),
      child: button,
    );
  }
}

/// Tombol sekunder Monex: outline halus, tanpa glow.
class MonexSecondaryButton extends StatelessWidget {
  const MonexSecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expanded = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        side: const BorderSide(color: MonexColors.borderLight),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontFamily: kMonexFontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

// ============================================================================
// 5.4. SEGMENTED CONTROL
// ============================================================================

/// Segmented control Monex (pill, satu segmen aktif).
class MonexSegmentedControl<T> extends StatelessWidget {
  const MonexSegmentedControl({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final List<MonexSegment<T>> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(MonexSpacing.radiusMd),
        border: Border.all(color: MonexColors.borderSubtle),
      ),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: _SegmentButton(
                label: item.label,
                icon: item.icon,
                selected: item.value == value,
                onTap: () => onChanged(item.value),
              ),
            ),
        ],
      ),
    );
  }
}

/// Satu segmen segmented control.
class MonexSegment<T> {
  const MonexSegment({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? MonexColors.limeMuted : Colors.transparent,
          borderRadius: BorderRadius.circular(MonexSpacing.radiusSm),
          border: Border.all(
            color: selected ? MonexColors.lime : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 15,
                color: selected ? MonexColors.lime : theme.textTheme.bodySmall!.color,
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: kMonexFontFamily,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? MonexColors.lime
                      : theme.textTheme.bodySmall!.color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 5.5. LIST TILE
// ============================================================================

/// Baris list Monex: ikon bulat + judul + subtitle + trailing.
class MonexTransactionTile extends StatelessWidget {
  const MonexTransactionTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leadingIcon,
    this.leadingColor,
    this.leadingBackground,
    this.trailing,
    this.onTap,
    this.titleStyle,
    this.subtitleStyle,
    this.padding = const EdgeInsets.symmetric(
      horizontal: MonexSpacing.cardPadding,
      vertical: 12,
    ),
  });

  final String title;
  final String? subtitle;
  final IconData? leadingIcon;
  final Color? leadingColor;
  final Color? leadingBackground;
  final Widget? trailing;
  final VoidCallback? onTap;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding,
          child: Row(
            children: [
              if (leadingIcon != null) ...[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: leadingBackground ?? MonexColors.limeMuted,
                    borderRadius: BorderRadius.circular(MonexSpacing.radiusSm),
                  ),
                  child: Icon(
                    leadingIcon,
                    size: 18,
                    color: leadingColor ?? MonexColors.lime,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: titleStyle ?? theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: subtitleStyle ?? theme.textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 10),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 5.6. PROGRESS
// ============================================================================

/// Progress bar Monex: track gelap, fill lime.
class MonexProgressBar extends StatelessWidget {
  const MonexProgressBar({
    super.key,
    required this.value,
    this.height = 8,
    this.color = MonexColors.lime,
    this.trackColor = MonexColors.chartTrack,
    this.animate = true,
  });

  /// 0.0 – 1.0. Nilai di luar rentang dijepit (edge-case safe).
  final double value;
  final double height;
  final Color color;
  final Color trackColor;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final clamped = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: clamped),
        duration: Duration(milliseconds: animate ? 600 : 0),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: height,
          backgroundColor: trackColor,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ),
    );
  }
}

// ============================================================================
// 5.7. CHART — mini vertical bars + spline
// ============================================================================

/// Bar chart vertikal mini (dipakai untuk tren & perbandingan).
class MonexMiniVerticalBars extends StatelessWidget {
  const MonexMiniVerticalBars({
    super.key,
    required this.values,
    this.height = 72,
    this.barColor = MonexColors.lime,
    this.trackColor = MonexColors.chartTrack,
    this.highlightIndex,
  });

  final List<double> values;
  final double height;
  final Color barColor;
  final Color trackColor;

  /// Indeks bar yang disorot (mis. nilai tertinggi).
  final int? highlightIndex;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Belum ada data',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }
    final maxV = values.reduce(math.max);
    final scale = maxV <= 0 ? 1.0 : maxV;
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: values[i] / scale),
                  duration: Duration(milliseconds: 420 + i * 60),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => Container(
                    height: height * (0.06 + 0.94 * v.clamp(0.0, 1.0)),
                    decoration: BoxDecoration(
                      color: i == highlightIndex
                          ? barColor
                          : barColor.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Grafik spline sederhana (tanpa package chart eksternal).
///
/// Menggambar kurva Catmull-Rom → Bézier. [points] boleh kosong: komponen
/// menampilkan placeholder, bukan crash.
class MonexSplineChart extends StatelessWidget {
  const MonexSplineChart({
    super.key,
    required this.points,
    this.height = 160,
    this.color = MonexColors.lime,
    this.fillColor = MonexColors.limeMuted,
    this.gridColor = MonexColors.chartTrack,
    this.strokeWidth = 2.5,
    this.showDots = true,
  });

  /// Urutan nilai (bukan koordinat). Sumbu Y dinormalisasi sendiri.
  final List<double> points;
  final double height;
  final Color color;
  final Color fillColor;
  final Color gridColor;
  final double strokeWidth;
  final bool showDots;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            points.isEmpty
                ? 'Belum ada data untuk digambar'
                : 'Perlu minimal 2 titik untuk grafik',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final maxV = points.reduce(math.max);
    final minV = points.reduce(math.min);
    final span = (maxV - minV).abs() < 1e-9 ? 1.0 : maxV - minV;

    return SizedBox(
      height: height,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => CustomPaint(
          painter: _SplinePainter(
            points: points,
            progress: t,
            color: color,
            fillColor: fillColor,
            gridColor: gridColor,
            strokeWidth: strokeWidth,
            showDots: showDots,
            minV: minV,
            span: span,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _SplinePainter extends CustomPainter {
  _SplinePainter({
    required this.points,
    required this.progress,
    required this.color,
    required this.fillColor,
    required this.gridColor,
    required this.strokeWidth,
    required this.showDots,
    required this.minV,
    required this.span,
  });

  final List<double> points;
  final double progress;
  final Color color;
  final Color fillColor;
  final Color gridColor;
  final double strokeWidth;
  final bool showDots;
  final double minV;
  final double span;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    // Grid horizontal tipis.
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = h * i / 4;
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    final dx = points.length == 1 ? w : w / (points.length - 1);
    final coords = <Offset>[];
    for (var i = 0; i < points.length; i++) {
      final normalized = ((points[i] - minV) / span).clamp(0.0, 1.0);
      final x = i * dx;
      final y = h - normalized * (h - 8) - 4;
      coords.add(Offset(x, y));
    }

    // Path spline (Catmull-Rom → cubic Bézier).
    final path = Path()..moveTo(coords.first.dx, coords.first.dy);
    for (var i = 0; i < coords.length - 1; i++) {
      final p0 = i == 0 ? coords[0] : coords[i - 1];
      final p1 = coords[i];
      final p2 = coords[i + 1];
      final p3 = i + 2 < coords.length ? coords[i + 2] : p2;
      final c1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
      );
      final c2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
      );
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }

    // Isian area di bawah kurva.
    final fillPath = Path.from(path)
      ..lineTo(coords.last.dx, h)
      ..lineTo(coords.first.dx, h)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [fillColor, fillColor.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // Garis kurva, digambar bertahap sesuai progres animasi.
    final metrics = path.computeMetrics();
    final total = metrics.fold<double>(0, (sum, m) => sum + m.length);
    if (total > 0) {
      for (final m in metrics) {
        canvas.drawPath(
          m.extractPath(0, total * progress.clamp(0.0, 1.0)),
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }

    // Titik data.
    if (showDots) {
      final dotPaint = Paint()..color = color;
      final haloPaint = Paint()..color = color.withValues(alpha: 0.22);
      final visible = (coords.length * progress.clamp(0.0, 1.0)).ceil();
      for (var i = 0; i < visible && i < coords.length; i++) {
        canvas.drawCircle(coords[i], 6, haloPaint);
        canvas.drawCircle(coords[i], 2.8, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SplinePainter old) =>
      old.progress != progress ||
      old.points != points ||
      old.color != color;
}

// ============================================================================
// 5.8. TOAST
// ============================================================================

/// Toast kustom Monex (pengganti SnackBar berat).
///
/// Pakai [ScaffoldMessenger] agar aman dari context tanpa Scaffold —
/// memanggil `showMonexToast` dari luar Scaffold tidak akan crash.
void showMonexToast(
  BuildContext context,
  String message, {
  bool isError = false,
  bool isSuccess = false,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final color = isError
      ? MonexColors.danger
      : isSuccess
          ? MonexColors.lime
          : MonexColors.surfaceElevated;
  final fg = (isError || isSuccess)
      ? MonexColors.textDark
      : Theme.of(context).colorScheme.onSurface;

  messenger.showSnackBar(
    SnackBar(
      backgroundColor: color,
      duration: const Duration(seconds: 3),
      content: Row(
        children: [
          Icon(
            isError
                ? Icons.error_outline_rounded
                : isSuccess
                    ? Icons.check_circle_outline_rounded
                    : Icons.info_outline_rounded,
            size: 18,
            color: fg,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: kMonexFontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ============================================================================
// 5.9. LOADING — animasi memukau (shimmer, pulse, orbit)
// ============================================================================

/// Placeholder shimmer: kotak yang "menyala" berulang.
///
/// Dibuat stateless (tanpa `AnimationController`) supaya aman dipakai di
/// dalam `ListView.builder` tanpa menambah controller per item.
class MonexShimmer extends StatefulWidget {
  const MonexShimmer({
    super.key,
    this.width = double.infinity,
    this.height = 14,
    this.radius = MonexSpacing.radiusSm,
  });

  final double width;
  final double height;
  final double radius;

  @override
  State<MonexShimmer> createState() => _MonexShimmerState();
}

class _MonexShimmerState extends State<MonexShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-1 - 2 * _c.value, 0),
                end: Alignment(1 - 2 * _c.value, 0),
                colors: [
                  base,
                  Color.lerp(base, MonexColors.lime, 0.18)!,
                  base,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Kerangka list yang "menyala" — dipakai saat data masih dimuat.
class MonexSkeletonList extends StatelessWidget {
  const MonexSkeletonList({
    super.key,
    this.itemCount = 4,
    this.hasLeading = true,
  });

  final int itemCount;
  final bool hasLeading;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(MonexSpacing.screenPaddingH),
      itemCount: itemCount,
      separatorBuilder: (_, _) => const SizedBox(height: MonexSpacing.gridGap),
      itemBuilder: (context, i) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasLeading) ...[
            const MonexShimmer(width: 38, height: 38, radius: 12),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MonexShimmer(
                  height: 13,
                  radius: 6,
                  width: i.isEven ? 160 : 110,
                ),
                const SizedBox(height: 8),
                const MonexShimmer(height: 10, radius: 5, width: 200),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Loader "orbit" — cincin lime berputar dengan inti berdenyut.
///
/// Dipakai sebagai loading state penuh layar yang tetap interaktif
/// (user bisa tetap scroll/keluar) dan bisa diberi [label].
class MonexOrbitLoader extends StatefulWidget {
  const MonexOrbitLoader({
    super.key,
    this.size = 64,
    this.label,
    this.message,
  });

  final double size;
  final String? label;
  final String? message;

  @override
  State<MonexOrbitLoader> createState() => _MonexOrbitLoaderState();
}

class _MonexOrbitLoaderState extends State<MonexOrbitLoader>
    with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              RotationTransition(
                turns: _spin,
                child: CustomPaint(
                  size: Size.square(widget.size),
                  painter: _OrbitPainter(
                    color: MonexColors.lime,
                    trackColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
              ScaleTransition(
                scale: Tween<double>(begin: 0.82, end: 1.0).animate(
                  CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                ),
                child: Container(
                  width: widget.size * 0.32,
                  height: widget.size * 0.32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: MonexColors.lime,
                    boxShadow: MonexDecorations.limeGlowShadow,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (widget.label != null) ...[
          const SizedBox(height: 18),
          Text(
            widget.label!,
            style: theme.textTheme.titleSmall,
            textAlign: TextAlign.center,
          ),
        ],
        if (widget.message != null) ...[
          const SizedBox(height: 6),
          Text(
            widget.message!,
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({required this.color, required this.trackColor});

  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 3;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    final sweep = math.pi * 0.75;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter old) =>
      old.color != color || old.trackColor != trackColor;
}

/// Loader "wave" — tiga titik berayun (untuk actions kecil).
class MonexWaveLoader extends StatefulWidget {
  const MonexWaveLoader({super.key, this.size = 8, this.color});

  final double size;
  final Color? color;

  @override
  State<MonexWaveLoader> createState() => _MonexWaveLoaderState();
}

class _MonexWaveLoaderState extends State<MonexWaveLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? MonexColors.lime;
    return SizedBox(
      height: widget.size,
      // 3 titik × (size + padding horizontal 6) = 3*size + 18.
      width: widget.size * 3 + 18,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Transform.translate(
                  offset: Offset(0, -math.sin((_c.value * 2 * math.pi) + i * 0.9) * 3),
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(
                        alpha: 0.45 + 0.55 * math.sin((_c.value * 2 * math.pi) + i * 0.9).abs(),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Overlay loading penuh dengan pesan — dipakai saat analyze/search berjalan.
///
/// [child] (bila ada) tetap terlihat di bawah overlay supaya konteks tidak
/// hilang; overlay bisa diketuk untuk membatalkan (via [onCancel]).
class MonexLoadingOverlay extends StatelessWidget {
  const MonexLoadingOverlay({
    super.key,
    required this.message,
    this.child,
    this.onCancel,
  });

  final String message;
  final Widget? child;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ?child,
        Positioned.fill(
          child: ColoredBox(
            color: MonexColors.canvas.withValues(alpha: 0.82),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const MonexOrbitLoader(size: 64),
                  const SizedBox(height: 18),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.titleSmall,
                    textAlign: TextAlign.center,
                  ),
                  if (onCancel != null) ...[
                    const SizedBox(height: 14),
                    MonexSecondaryButton(
                      label: 'Batal',
                      icon: Icons.close_rounded,
                      expanded: false,
                      onPressed: onCancel,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// 5.10. BOTTOM NAV + FAB
// ============================================================================

/// Bottom navigation Monex.
///
///仍然是 [NavigationBar] di bawah (type-nya dipertahankan agar semantics
/// & test lama tetap jalan); yang berubah adalah visual: surface penuh,
/// border atas halus, ikon lime saat aktif.
class MonexBottomNavBar extends StatelessWidget {
  const MonexBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.items,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<MonexNavItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: MonexColors.borderSubtle),
        ),
      ),
      child: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelected,
        destinations: [
          for (final item in items)
            NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon ?? item.icon),
              label: item.label,
            ),
        ],
      ),
    );
  }
}

/// Satu item bottom navigation.
class MonexNavItem {
  const MonexNavItem({
    required this.icon,
    required this.label,
    this.selectedIcon,
  });

  final IconData icon;
  final IconData? selectedIcon;
  final String label;
}

/// FAB Monex: lingkaran lime dengan glow neon (DESIGN(reset) §5.6).
class MonexFab extends StatelessWidget {
  const MonexFab({
    super.key,
    required this.onPressed,
    this.icon = Icons.add_rounded,
    this.tooltip,
    this.size = 56,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fab = FloatingActionButton(
      onPressed: onPressed,
      backgroundColor: MonexColors.lime,
      foregroundColor: MonexColors.textDark,
      elevation: 0,
      highlightElevation: 0,
      tooltip: tooltip,
      shape: const CircleBorder(),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: MonexDecorations.limeGlowShadow,
        ),
        child: Icon(icon, size: size * 0.5),
      ),
    );
    return fab;
  }
}

// ============================================================================
// 5.11. EMPTY STATE
// ============================================================================

/// Empty state: ikon, judul, pesan, dan aksi opsional.
class MonexEmptyState extends StatelessWidget {
  const MonexEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(MonexSpacing.screenPaddingH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: MonexColors.limeMuted,
                borderRadius: BorderRadius.circular(MonexSpacing.radiusCard),
              ),
              child: Icon(icon, size: 32, color: MonexColors.lime),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              MonexPrimaryButton(
                label: actionLabel!,
                onPressed: onAction,
                expanded: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
