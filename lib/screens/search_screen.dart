import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthbang/core/theme/monex_theme.dart';
import 'package:worthbang/core/widgets/monex_widgets.dart';
import 'package:worthbang/services/core/api_exception.dart';
import 'package:worthbang/services/core/api_result.dart';
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
    } catch (e) {
      final message = e is ApiException ? e.message : e.toString();
      if (!mounted) return;
      setState(() => _state = ApiError(message));
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
