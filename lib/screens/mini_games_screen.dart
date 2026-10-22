import 'package:flutter/material.dart';

import 'package:worthbang/core/theme/monex_theme.dart';
import 'package:worthbang/core/widgets/monex_widgets.dart';
import 'package:worthbang/l10n/strings.dart';
import 'package:worthbang/screens/game_screen.dart';
import 'package:worthbang/screens/zero_g_thermal_screen.dart';

/// Hub Mini Games: satu menu di Beranda yang membuka pilihan dua game —
/// Tebak Harga dan Zero-G Thermal.
class MiniGamesScreen extends StatelessWidget {
  const MiniGamesScreen({super.key});

  void _openPage(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.miniGamesTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          MonexSpacing.screenPaddingH,
          MonexSpacing.screenPaddingV,
          MonexSpacing.screenPaddingH,
          24,
        ),
        children: [
          _GameChoiceCard(
            title: AppStrings.gameTitle,
            subtitle: AppStrings.homeGameSubtitle,
            icon: Icons.sports_esports_outlined,
            onTap: () => _openPage(context, const GameScreen()),
          ),
          const SizedBox(height: MonexSpacing.gridGap),
          _GameChoiceCard(
            title: AppStrings.zeroGTitle,
            subtitle: AppStrings.zeroGSubtitle,
            icon: Icons.developer_board_rounded,
            onTap: () => _openPage(context, const ZeroGThermalScreen()),
          ),
        ],
      ),
    );
  }
}

class _GameChoiceCard extends StatelessWidget {
  const _GameChoiceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MonexSurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(20),
      radius: MonexSpacing.radiusMd,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: MonexColors.limeMuted,
              borderRadius: BorderRadius.circular(MonexSpacing.radiusSm),
            ),
            child: Icon(icon, size: 24, color: MonexColors.lime),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_forward_rounded),
        ],
      ),
    );
  }
}
