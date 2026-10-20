import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthbang/core/theme/monex_theme.dart';
import 'package:worthbang/core/widgets/monex_widgets.dart';
import 'package:worthbang/providers/providers.dart';
import 'package:worthbang/services/api_result.dart';
import 'package:worthbang/l10n/strings.dart';
import 'package:worthbang/screens/builder_screen.dart';
import 'package:worthbang/screens/chat_screen.dart';
import 'package:worthbang/screens/game_screen.dart';
import 'package:worthbang/screens/stores_screen.dart';
import 'package:worthbang/screens/tools_screen.dart';
import 'package:worthbang/screens/wishlist_screen.dart';
import 'package:worthbang/services/history_repository.dart';
import 'package:worthbang/models/price_check_models.dart';
import 'package:worthbang/services/price_check_api.dart';
import 'result_screen.dart';
import 'bundle_screen.dart';

final priceCheckApiProvider = Provider<PriceCheckApi>(
  (ref) => PriceCheckApi(),
);

final historyRepositoryProvider = Provider<HistoryRepository>(
  (ref) => HistoryRepository(ref.watch(databaseProvider)),
);

/// Layar utama Beranda: form cek harga + autocomplete (debounce 300ms).
class PriceCheckScreen extends ConsumerStatefulWidget {
  const PriceCheckScreen({super.key});

  @override
  ConsumerState<PriceCheckScreen> createState() => _PriceCheckScreenState();
}

class _PriceCheckScreenState extends ConsumerState<PriceCheckScreen> {
  final _formKey = GlobalKey<FormState>();
  final _query = TextEditingController();
  final _price = TextEditingController();

  String _mode = 'pc';
  String _condition = 'any';
  List<String> _suggestions = [];
  Timer? _debounce;
  ApiResult<AnalysisResult>? _state;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _price.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final list = await ref
          .read(priceCheckApiProvider)
          .suggest(section: _mode, query: value);
      if (mounted) setState(() => _suggestions = list);
    });
  }

  int? _parsePrice(String raw) {
    final digits = int.tryParse(raw.replaceAll(RegExp(r'[^0-9]'), ''));
    return (digits == null || digits <= 0) ? null : digits;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _state = const ApiLoading());
    try {
      final result = await ref.read(priceCheckApiProvider).analyze(
            mode: _mode,
            query: _query.text.trim(),
            price: _parsePrice(_price.text) ?? 0,
            condition: _condition,
          );
      setState(() => _state = ApiSuccess(result));
      if (!mounted) return;
      // Simpan ke hash chain, lalu buka layar hasil.
      final block =
          await ref.read(historyRepositoryProvider).appendAnalysis(result);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ResultScreen(result: result, blockId: block.id),
        ),
      );
    } catch (e) {
      setState(() => _state = ApiError(e.toString()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final String? errorMessage =
        state is ApiError<AnalysisResult> ? state.message : null;
    final bool isLoading = state is ApiLoading<AnalysisResult>;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.priceCheckTitle),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.apps_outlined),
            tooltip: AppStrings.moreFeatures,
            onSelected: (v) {
              final Widget page = switch (v) {
                'builder' => const BuilderScreen(),
                'stores' => const StoresScreen(),
                'tools' => const ToolsScreen(),
                'wishlist' => const WishlistAlertsScreen(),
                'game' => const GameScreen(),
                'chat' => const ChatScreen(),
                _ => const SizedBox.shrink(),
              };
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => page),
              );
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'builder',
                child: ListTile(
                  leading: Icon(Icons.handyman_outlined),
                  title: Text(AppStrings.builderTitle),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'stores',
                child: ListTile(
                  leading: Icon(Icons.store_outlined),
                  title: Text(AppStrings.storesTitle),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'tools',
                child: ListTile(
                  leading: Icon(Icons.calculate_outlined),
                  title: Text(AppStrings.toolsTitle),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'wishlist',
                child: ListTile(
                  leading: Icon(Icons.favorite_outline),
                  title: Text(AppStrings.wishlistTitle),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'game',
                child: ListTile(
                  leading: Icon(Icons.sports_esports_outlined),
                  title: Text(AppStrings.gameTitle),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'chat',
                child: ListTile(
                  leading: Icon(Icons.smart_toy_outlined),
                  title: Text(AppStrings.chatTitle),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            MonexSpacing.screenPaddingH,
            MonexSpacing.screenPaddingV,
            MonexSpacing.screenPaddingH,
            24,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MonexSegmentedControl<String>(
                  value: _mode,
                  onChanged: (v) => setState(() => _mode = v),
                  items: const [
                    MonexSegment(
                      value: 'pc',
                      label: 'Komponen PC',
                      icon: Icons.memory_outlined,
                    ),
                    MonexSegment(
                      value: 'laptop',
                      label: 'Laptop',
                      icon: Icons.laptop_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: MonexSpacing.sectionGap),
                TextFormField(
                  controller: _query,
                  onChanged: _onQueryChanged,
                  decoration: const InputDecoration(
                    labelText: AppStrings.queryLabel,
                    hintText: AppStrings.queryHint,
                    prefixIcon: Icon(Icons.search),
                  ),
                  validator: (v) => (v == null || v.trim().length < 2)
                      ? AppStrings.queryMin
                      : null,
                ),
                if (_suggestions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  MonexSurfaceCard(
                    padding: EdgeInsets.zero,
                    radius: MonexSpacing.radiusMd,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final s in _suggestions)
                          MonexTransactionTile(
                            title: s,
                            leadingIcon: Icons.history,
                            leadingBackground:
                                theme.colorScheme.surfaceContainerHighest,
                            leadingColor: theme.textTheme.bodySmall!.color,
                            onTap: () {
                              _query.text = s;
                              setState(() => _suggestions = []);
                            },
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: MonexSpacing.sectionGap),
                TextFormField(
                  controller: _price,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: AppStrings.priceLabel,
                    prefixText: 'Rp ',
                  ),
                  validator: (v) => _parsePrice(v ?? '') == null
                      ? AppStrings.priceInvalid
                      : null,
                ),
                const SizedBox(height: MonexSpacing.sectionGap),
                DropdownButtonFormField<String>(
                  initialValue: _condition,
                  // isExpanded: teks item diberi ruang lentur, jadi label
                  // panjang tidak memaksa Row melebar di layar 320 px.
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: AppStrings.conditionLabel,
                    prefixIcon: Icon(Icons.sell_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'any', child: Text('Semua kondisi')),
                    DropdownMenuItem(value: 'baru', child: Text('Baru')),
                    DropdownMenuItem(value: 'bekas', child: Text('Bekas')),
                  ],
                  onChanged: (v) => setState(() => _condition = v ?? 'any'),
                ),
                const SizedBox(height: MonexSpacing.sectionGap + 6),
                MonexPrimaryButton(
                  label: AppStrings.checkButton,
                  icon: Icons.analytics_outlined,
                  loading: isLoading,
                  onPressed: isLoading ? null : _submit,
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorMessage,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 10),
                MonexSecondaryButton(
                  label: AppStrings.bundleModeButton,
                  icon: Icons.inventory_2_outlined,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const BundleScreen()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
