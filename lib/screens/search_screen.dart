import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:worthbang/core/theme/monex_theme.dart';
import 'package:worthbang/core/widgets/monex_widgets.dart';
import 'package:worthbang/services/core/api_exception.dart';
import 'package:worthbang/services/core/api_result.dart';
import 'package:worthbang/services/data/local_catalog.dart';
import 'package:worthbang/services/features/personalization/personalization_engine.dart';
import 'package:worthbang/utils/rupiah.dart';
import 'package:worthbang/l10n/strings.dart';
import 'package:worthbang/models/price_check_models.dart';
import 'package:worthbang/screens/price_check_screen.dart';
import 'package:worthbang/models/search_filter.dart';

/// Tab Cari: cari produk → filter (kondisi/sumber/harga maks) + sort.
class SearchFilterScreen extends ConsumerStatefulWidget {
  const SearchFilterScreen({super.key});

  @override
  ConsumerState<SearchFilterScreen> createState() => _SearchFilterScreenState();
}

class _SearchFilterScreenState extends ConsumerState<SearchFilterScreen> {
  final _query = TextEditingController();
  final _maxPrice = TextEditingController();

  String _mode = 'pc';
  ApiResult<List<PriceComparison>>? _state;
  SearchFilter _filter = const SearchFilter();

  @override
  void dispose() {
    _query.dispose();
    _maxPrice.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final queryText = _query.text.trim();
    if (queryText.length < 2) {
      showMonexToast(context, AppStrings.queryMin, isError: true);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _state = const ApiLoading());
    try {
      final comparisons = await ref
          .read(priceCheckApiProvider)
          .search(mode: _mode, query: queryText);
      if (!mounted) return;
      setState(() => _state = ApiSuccess(comparisons));
      _recordSearch(queryText);
    } catch (e) {
      final message = e is ApiException ? e.message : e.toString();
      if (!mounted) return;
      setState(() => _state = ApiError(message));
    }
  }

  /// Catat event pencarian untuk personalisasi (best-effort, tidak
  /// pernah mengganggu alur pencarian).
  Future<void> _recordSearch(String queryText) async {
    try {
      final engine =
          PersonalizationEngine(await SharedPreferences.getInstance());
      await engine.record(UserEvent(
        type: UserEventType.search,
        category: _mode,
        query: queryText,
        at: DateTime.now(),
      ));
    } catch (_) {
      // Telemetri personalisasi gagal = diam saja.
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final queryText = _query.text.trim();
    final comparisons = state is ApiSuccess<List<PriceComparison>>
        ? state.data
        : null;
    final filtered = comparisons != null
        ? _filter.apply(comparisons)
        : const <PriceComparison>[];
    final sources = comparisons?.map((c) => c.source).toSet().toList() ?? [];

    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.searchScreenTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            MonexSpacing.screenPaddingH,
            MonexSpacing.screenPaddingV,
            MonexSpacing.screenPaddingH,
            24,
          ),
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
                  icon: Icons.laptop_mac_outlined,
                ),
              ],
            ),
            const SizedBox(height: MonexSpacing.sectionGap),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _query,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      labelText: AppStrings.queryLabel,
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                MonexPrimaryButton(
                  label: AppStrings.searchButton,
                  expanded: false,
                  loading: state is ApiLoading,
                  onPressed: state is ApiLoading ? null : _search,
                ),
              ],
            ),
            if (state == null) ...[
              const SizedBox(height: MonexSpacing.sectionGap),
              const _ForYouSection(),
            ],
            if (state is ApiLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: MonexOrbitLoader(size: 56)),
              ),
            if (state is ApiError)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  (state as ApiError<List<PriceComparison>>).message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (comparisons != null) ...[
              const SizedBox(height: 16),
              Text(
                '$queryText — ${filtered.length} dari ${comparisons.length} listing',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('Baru'),
                    selected: _filter.conditions.contains('baru'),
                    onSelected: (v) => setState(() {
                      final s = Set<String>.from(_filter.conditions);
                      v ? s.add('baru') : s.remove('baru');
                      _filter = _filter.copyWith(conditions: s);
                    }),
                  ),
                  FilterChip(
                    label: const Text('Bekas'),
                    selected: _filter.conditions.contains('bekas'),
                    onSelected: (v) => setState(() {
                      final s = Set<String>.from(_filter.conditions);
                      v ? s.add('bekas') : s.remove('bekas');
                      _filter = _filter.copyWith(conditions: s);
                    }),
                  ),
                  for (final src in sources)
                    FilterChip(
                      label: Text(src),
                      selected: _filter.sources.contains(src),
                      onSelected: (v) => setState(() {
                        final s = Set<String>.from(_filter.sources);
                        v ? s.add(src) : s.remove(src);
                        _filter = _filter.copyWith(sources: s);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _maxPrice,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: AppStrings.maxPriceLabel,
                        prefixText: 'Rp ',
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() {
                        final n = int.tryParse(
                          v.replaceAll(RegExp(r'[^0-9]'), ''),
                        );
                        _filter = _filter.copyWith(
                          maxPrice: () => n == null || n <= 0 ? null : n,
                        );
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<SortOption>(
                      initialValue: _filter.sort,
                      decoration: const InputDecoration(
                        labelText: AppStrings.sortLabel,
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: SortOption.priceAsc,
                          child: Text('Harga terendah'),
                        ),
                        DropdownMenuItem(
                          value: SortOption.priceDesc,
                          child: Text('Harga tertinggi'),
                        ),
                        DropdownMenuItem(
                          value: SortOption.similarity,
                          child: Text('Paling mirip'),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _filter = _filter.copyWith(sort: v)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final c in filtered)
                Padding(
                  padding: const EdgeInsets.only(bottom: MonexSpacing.gridGap),
                  child: MonexSurfaceCard(
                    padding:
                        const EdgeInsets.all(MonexSpacing.cardPaddingCompact),
                    radius: MonexSpacing.radiusMd,
                    child: MonexTransactionTile(
                      title: c.title,
                      titleStyle: theme.textTheme.titleSmall,
                      subtitle:
                          '${c.source}${switch (c.condition) {
                        'new' => ' • baru',
                        'second' => ' • bekas',
                        final condition => condition == null ? '' : ' • $condition',
                      }}',
                      padding: EdgeInsets.zero,
                      trailing: Text(
                        formatRupiah(c.price),
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                  ),
                ),
              if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text(AppStrings.searchEmpty)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Section 'Buat Kamu': etalase awal menu Cari — 20 produk teratas
/// hasil rank() personalisasi lokal atas seluruh katalog bundel.
/// Ketuk kartu = event viewDetail.
class _ForYouSection extends StatefulWidget {
  const _ForYouSection();

  @override
  State<_ForYouSection> createState() => _ForYouSectionState();
}

class _ForYouSectionState extends State<_ForYouSection> {
  List<ScoredProduct>? _top;
  Map<String, String> _categoryOf = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final engine =
        PersonalizationEngine(await SharedPreferences.getInstance());
    final items = await LocalCatalog.allItems();
    final ranked = engine.rank(items);
    final byCategory = await LocalCatalog.load();
    final categoryOf = <String, String>{};
    byCategory.forEach((category, list) {
      for (final item in list) {
        categoryOf.putIfAbsent(item.model, () => category);
      }
    });
    // Urutan etalase = acak terbobot di kelompok skor atas (mesin
    // showcase); skor & alasan tetap diambil dari rank().
    final byModel = {for (final s in ranked) s.item.model: s};
    final order = engine.showcase(
      items,
      limit: 20,
      rng: Random(DateTime.now().millisecondsSinceEpoch),
    );
    final top = order
        .map((it) => byModel[it.model])
        .whereType<ScoredProduct>()
        .toList();
    if (!mounted) return;
    setState(() {
      _top = top;
      _categoryOf = categoryOf;
    });
  }

  Future<void> _recordView(ScoredProduct product) async {
    try {
      final engine =
          PersonalizationEngine(await SharedPreferences.getInstance());
      await engine.record(UserEvent(
        type: UserEventType.viewDetail,
        category: _categoryOf[product.item.model],
        productName: product.item.model,
        price: product.item.price,
        at: DateTime.now(),
      ));
    } catch (_) {
      // Telemetri personalisasi gagal = diam saja.
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = _top;
    if (top == null || top.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppStrings.showcaseTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(AppStrings.showcaseSubtitle, style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        for (final product in top)
          Padding(
            padding: const EdgeInsets.only(bottom: MonexSpacing.gridGap),
            child: MonexSurfaceCard(
              onTap: () => _recordView(product),
              padding:
                  const EdgeInsets.all(MonexSpacing.cardPaddingCompact),
              radius: MonexSpacing.radiusMd,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MonexTransactionTile(
                    title: product.item.model,
                    titleStyle: theme.textTheme.titleSmall,
                    subtitle: _categoryOf[product.item.model] ?? '',
                    padding: EdgeInsets.zero,
                    trailing: Text(
                      formatRupiah(product.item.price),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (product.reason != null &&
                      product.reason!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Chip(
                      label: Text(product.reason!),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
