import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthbang/core/theme/monex_theme.dart';
import 'package:worthbang/core/widgets/monex_widgets.dart';
import 'package:worthbang/l10n/strings.dart';
import 'package:worthbang/l10n/dream_strings.dart';
import 'package:worthbang/screens/builder_screen.dart';
import 'package:worthbang/screens/dream_build_screen.dart';
import 'package:worthbang/screens/chat_screen.dart';
import 'package:worthbang/screens/history_screen.dart';
import 'package:worthbang/screens/mini_games_screen.dart';
import 'package:worthbang/screens/price_check_screen.dart';
import 'package:worthbang/screens/result_screen.dart';
import 'package:worthbang/screens/scan_price_screen.dart';
import 'package:worthbang/screens/search_screen.dart';
import 'package:worthbang/screens/stores_screen.dart';
import 'package:worthbang/screens/tools_screen.dart';
import 'package:worthbang/screens/wishlist_screen.dart';
import 'package:worthbang/services/features/scan_price_service.dart';
import 'package:worthbang/widgets/app_logo.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static final _menus = <_HomeMenuItem>[
    _HomeMenuItem(
      title: AppStrings.builderTitle,
      subtitle: AppStrings.homeBuilderSubtitle,
      icon: Icons.handyman_outlined,
      page: (_) => const BuilderScreen(),
    ),
    _HomeMenuItem(
      title: AppStrings.searchScreenTitle,
      subtitle: AppStrings.homeSearchSubtitle,
      icon: Icons.search_rounded,
      page: (_) => const SearchFilterScreen(),
    ),
    _HomeMenuItem(
      title: AppStrings.storesTitle,
      subtitle: AppStrings.homeStoresSubtitle,
      icon: Icons.store_outlined,
      page: (_) => const StoresScreen(),
    ),
    _HomeMenuItem(
      title: AppStrings.toolsTitle,
      subtitle: AppStrings.homeToolsSubtitle,
      icon: Icons.calculate_outlined,
      page: (_) => const ToolsScreen(),
    ),
    _HomeMenuItem(
      title: AppStrings.wishlistTitle,
      subtitle: AppStrings.homeWishlistSubtitle,
      icon: Icons.favorite_border_rounded,
      page: (_) => const WishlistAlertsScreen(),
    ),
    _HomeMenuItem(
      title: DreamStrings.title,
      subtitle: DreamStrings.homeSubtitle,
      icon: Icons.rocket_launch_outlined,
      page: (_) => const DreamBuildScreen(),
    ),
    _HomeMenuItem(
      title: AppStrings.miniGamesTitle,
      subtitle: AppStrings.homeMiniGamesSubtitle,
      icon: Icons.sports_esports_outlined,
      page: (_) => const MiniGamesScreen(),
    ),
    _HomeMenuItem(
      title: AppStrings.chatTitle,
      subtitle: AppStrings.homeChatSubtitle,
      icon: Icons.smart_toy_outlined,
      page: (_) => const ChatScreen(),
    ),
    // Shortcut Pindai Harga: mode/kondisi default sama seperti _submit
    // di PriceCheckScreen (pc / any); callback memakai container Riverpod
    // dari context karena HomeScreen bukan Consumer.
    _HomeMenuItem(
      title: AppStrings.scanPriceTitle,
      subtitle: AppStrings.scanPriceSubtitle,
      icon: Icons.document_scanner_outlined,
      page: (context) => ScanPriceScreen(
        scanService: MlKitScanPriceService(),
        onAnalyzeRequested: (ctx, query, price) async {
          final container = ProviderScope.containerOf(ctx);
          final result = await container.read(priceCheckApiProvider).analyze(
                mode: 'pc',
                query: query,
                price: price,
                condition: 'any',
              );
          final block = await container
              .read(historyRepositoryProvider)
              .appendAnalysis(result);
          if (!ctx.mounted) return;
          Navigator.of(ctx).push(
            MaterialPageRoute(
              builder: (_) => ResultScreen(result: result, blockId: block.id),
            ),
          );
        },
        onFallbackManual: (ctx, {initialQuery}) {
          Navigator.of(ctx).push(
            MaterialPageRoute(
              builder: (_) => PriceCheckScreen(initialQuery: initialQuery),
            ),
          );
        },
      ),
    ),
  ];

  void _openPage(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const Padding(
          padding: EdgeInsets.all(8),
          child: AppLogo(size: 40, borderRadius: 10),
        ),
        title: const Text(AppStrings.homeTitle),
        titleSpacing: 4,
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: AppStrings.historyScreenTitle,
            onPressed: () => _openPage(context, const HistoryListScreen()),
          ),
        ],
      ),
      // FAB khusus chatbot, HANYA di Beranda root: FAB tinggal di
      // Scaffold ini, jadi otomatis tertutup tiap user masuk menu
      // (halaman push menutupi Beranda) dan tidak tampil di tab lain.
      floatingActionButton: MonexFab(
        icon: Icons.smart_toy_outlined,
        tooltip: AppStrings.chatTitle,
        onPressed: () => _openPage(context, const ChatScreen()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          MonexSpacing.screenPaddingH,
          MonexSpacing.screenPaddingV,
          MonexSpacing.screenPaddingH,
          24,
        ),
        children: [
          Text(
            AppStrings.homeGreeting,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppStrings.appTagline,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: MonexSpacing.sectionGap),
          // Hero card — 3D Cyber Tech Banner dengan Ilustrasi Hardware GPU Holografik.
          _HomeHeroBanner(
            onTap: () => _openPage(context, const PriceCheckScreen()),
          ),
          const SizedBox(height: MonexSpacing.sectionGap),
          Text(
            AppStrings.homeExploreTitle,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: MonexSpacing.gridGap),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 600 ? 3 : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _menus.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: MonexSpacing.gridGap,
                  mainAxisSpacing: MonexSpacing.gridGap,
                  // Rasio adjusted supaya judul 2 baris + subtitle 2 baris
                  // tidak overflow di layar sempit (320dp) dengan efek kartu bertumpuk.
                  childAspectRatio: columns == 2 ? 0.98 : 0.92,
                ),
                itemBuilder: (context, index) {
                  final menu = _menus[index];
                  return _HomeMenuCard(
                    item: menu,
                    onTap: () => _openPage(context, menu.page(context)),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HomeMenuItem {
  const _HomeMenuItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.page,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget Function(BuildContext context) page;
}

class _HomeMenuCard extends StatelessWidget {
  const _HomeMenuCard({
    required this.item,
    required this.onTap,
  });

  final _HomeMenuItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Shade warna layer belakang kartu bertumpuk (stacked card effect)
    final backCardColor = isDark
        ? MonexColors.surfaceElevated
        : const Color(0xFFE2E8F0);
    final backBorderColor = isDark
        ? MonexColors.borderLight
        : theme.colorScheme.outlineVariant;

    return Stack(
      children: [
        // Kartu layer belakang (shade berbeda untuk ilusi kartu ditumpuk)
        Positioned(
          top: 4,
          left: 4,
          right: 0,
          bottom: 0,
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: backCardColor,
                borderRadius: BorderRadius.circular(MonexSpacing.radiusMd),
                border: Border.all(
                  color: backBorderColor,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: isDark ? 0.30 : 0.08,
                    ),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Kartu layer utama di atas tumpukan
        Positioned(
          top: 0,
          left: 0,
          right: 4,
          bottom: 4,
          child: MonexSurfaceCard(
            onTap: onTap,
            padding: const EdgeInsets.all(MonexSpacing.cardPaddingCompact),
            radius: MonexSpacing.radiusMd,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: MonexColors.limeMuted,
                    borderRadius:
                        BorderRadius.circular(MonexSpacing.radiusSm),
                  ),
                  child: Icon(item.icon, size: 20, color: MonexColors.lime),
                ),
                const SizedBox(height: 8),
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Text(
                    item.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeHeroBanner extends StatelessWidget {
  const _HomeHeroBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(MonexSpacing.radiusCard),
        border: Border.all(
          color: MonexColors.lime.withValues(alpha: isDark ? 0.32 : 0.45),
          width: 1.2,
        ),
        gradient: LinearGradient(
          colors: isDark
              ? const [
                  Color(0xFF1B2332), // Dark slate navy
                  Color(0xFF111622), // Deep surface
                  Color(0xFF090D14), // Canvas edge
                ]
              : const [
                  Color(0xFFF8FAFC),
                  Color(0xFFF1F5F9),
                  Color(0xFFE2E8F0),
                ],
          stops: const [0.0, 0.55, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: MonexColors.lime.withValues(alpha: isDark ? 0.14 : 0.08),
            blurRadius: 22,
            spreadRadius: -4,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(MonexSpacing.radiusCard),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(MonexSpacing.radiusCard),
          child: Stack(
            children: [
              // Ambient radial neon glow di belakang ilustrasi 3D
              Positioned(
                right: -20,
                top: -20,
                width: 170,
                height: 170,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        MonexColors.lime.withValues(alpha: isDark ? 0.22 : 0.15),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              // Ilustrasi 3D GPU hardware peeking dari sisi kanan
              Positioned(
                right: -6,
                top: -6,
                bottom: -6,
                width: 136,
                child: ShaderMask(
                  shaderCallback: (rect) {
                    return const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.transparent,
                        Colors.black,
                        Colors.black,
                      ],
                      stops: [0.0, 0.35, 1.0],
                    ).createShader(rect);
                  },
                  blendMode: BlendMode.dstIn,
                  child: Image.asset(
                    'assets/images/hero_tech_gpu.jpg',
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: MonexColors.surfaceHover,
                      child: const Icon(
                        Icons.memory_rounded,
                        color: MonexColors.lime,
                        size: 40,
                      ),
                    ),
                  ),
                ),
              ),
              // Konten teks & call-to-action di sisi kiri
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: MonexColors.limeMuted,
                        borderRadius:
                            BorderRadius.circular(MonexSpacing.radiusPill),
                        border: Border.all(
                          color: MonexColors.lime.withValues(alpha: 0.35),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.auto_awesome_rounded,
                            size: 11,
                            color: MonexColors.lime,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'AI EVALUATOR',
                            style: TextStyle(
                              fontFamily: kMonexFontFamily,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: isDark
                                  ? MonexColors.lime
                                  : const Color(0xFF3B7A00),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 190),
                      child: Text(
                        AppStrings.priceCheckTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: isDark
                              ? MonexColors.textPrimary
                              : const Color(0xFF0F172A),
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(
                        AppStrings.homePriceCheckSubtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? MonexColors.textSecondary
                              : const Color(0xFF475569),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: MonexColors.lime,
                        borderRadius:
                            BorderRadius.circular(MonexSpacing.radiusPill),
                        boxShadow: MonexDecorations.limeGlowShadow,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Cek Sekarang',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: MonexColors.textDark,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            size: 14,
                            color: MonexColors.textDark,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

