import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthbang/screens/history_screen.dart';
import 'package:worthbang/screens/price_check_screen.dart';
import 'package:worthbang/screens/profile_screen.dart';
import 'package:worthbang/screens/result_screen.dart';
import 'package:worthbang/screens/scan_price_screen.dart';
import 'package:worthbang/screens/search_screen.dart';
import 'package:worthbang/services/features/scan_price_service.dart';

export 'home_screen.dart' show HomeScreen;

/// Tab Cari: filter & sort hasil (T5).
class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) => const SearchFilterScreen();
}

/// Tab Pindai Harga: OCR struk/label harga + analisis worth-it.
class ScanPriceTabScreen extends ConsumerWidget {
  const ScanPriceTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scanService = ref.watch(scanPriceServiceProvider);
    return ScanPriceScreen(
      scanService: scanService,
      onAnalyzeRequested: (ctx, query, price) async {
        final result = await ref.read(priceCheckApiProvider).analyze(
              mode: 'pc',
              query: query,
              price: price,
              condition: 'any',
            );
        final block = await ref
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
    );
  }
}

/// Tab Riwayat: daftar + verifikasi hash chain (T6).
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) => const HistoryListScreen();
}

/// Tab Profil (T14).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) => const ProfileContentScreen();
}
