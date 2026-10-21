import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:worthbang/core/theme/monex_theme.dart';
import 'package:worthbang/core/widgets/monex_widgets.dart';
import 'package:worthbang/services/core/api_exception.dart';
import 'package:worthbang/services/core/api_result.dart';
import 'package:worthbang/services/data/local_catalog.dart';
import 'package:worthbang/services/data/products_catalog.dart';
import 'package:worthbang/services/features/personalization/personalization_engine.dart';
import 'package:worthbang/utils/rupiah.dart';
import 'package:worthbang/widgets/price_conversion_card.dart';
import 'package:worthbang/l10n/strings.dart';
import 'package:worthbang/models/price_check_models.dart';
import 'package:worthbang/screens/onboarding_screen.dart';
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
  final _forYouKey = GlobalKey<_ForYouSectionState>();

  String _mode = 'pc';
  ApiResult<List<PriceComparison>>? _state;
  SearchFilter _filter = const SearchFilter();

  /// Gerbang onboarding personalisasi: ditawarkan maksimal sekali per
  /// sesi aplikasi, saat menu Cari PERTAMA kali dibuka, dan hanya bila
  /// user belum pernah mengisinya (keputusan Dan: bukan di Beranda).
  static bool _onboardingPrompted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybePromptOnboarding();
    });
  }

  Future<void> _maybePromptOnboarding() async {
    if (_onboardingPrompted) return;
    _onboardingPrompted = true;
    try {
      final engine =
          PersonalizationEngine(await SharedPreferences.getInstance());
      if (await engine.hasOnboarding()) return;
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const OnboardingScreen()),
      );
      if (!mounted) return;
      // Profil berubah (atau dilewati) -> muat ulang etalase.
      await _forYouKey.currentState?.reload();
    } catch (_) {
      // Gerbang onboarding gagal = diam saja, menu Cari tetap jalan.
    }
  }

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
              _ForYouSection(key: _forYouKey, mode: _mode),
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

/// Satu kartu etalase: produk ternormalisasi + alasan personalisasi.
class _ShowcaseItem {
  const _ShowcaseItem(this.product, this.reason);

  final NormalizedProduct product;
  final String? reason;
}

/// Section 'Buat Kamu': etalase awal menu Cari — grid produk
/// ternormalisasi (ProductsCatalog) yang diurutkan mesin
/// personalisasi lokal. Urutan = showcase() acak terbobot di kelompok
/// skor atas; alasan dari rank(). Ketuk kartu = event viewDetail,
/// lalu buka Cek Harga dengan nama produk terisi.
class _ForYouSection extends StatefulWidget {
  const _ForYouSection({super.key, required this.mode});

  /// Mode section menu Cari ('pc' | 'laptop'): etalase mengikuti —
  /// 'laptop' hanya produk laptop, 'pc' semua selain laptop.
  final String mode;

  @override
  State<_ForYouSection> createState() => _ForYouSectionState();
}

class _ForYouSectionState extends State<_ForYouSection> {
  List<_ShowcaseItem>? _top;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_ForYouSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) _load();
  }

  /// Muat (ulang) etalase — dipanggil juga setelah onboarding selesai
  /// agar urutan langsung memakai profil baru.
  Future<void> reload() => _load();

  Future<void> _load() async {
    final mode = widget.mode;
    final all = await ProductsCatalog.load();
    final products = [
      for (final p in all)
        if (mode == 'laptop' ? p.category == 'laptop' : p.category != 'laptop')
          p,
    ];
    if (products.isEmpty) {
      if (mounted && widget.mode == mode) setState(() => _top = const []);
      return;
    }
    final engine =
        PersonalizationEngine(await SharedPreferences.getInstance());
    // Mesin personalisasi bekerja atas CatalogItem: adaptasikan
    // produk ternormalisasi, lalu petakan balik via nama.
    final adapters = [
      for (final p in products) CatalogItem(model: p.name, price: p.price),
    ];
    final ranked = engine.rank(adapters);
    final reasonOf = {for (final s in ranked) s.item.model: s.reason};
    final productOf = {for (final p in products) p.name: p};
    final order = engine.showcase(
      adapters,
      limit: 20,
      rng: Random(DateTime.now().millisecondsSinceEpoch),
    );
    final top = [
      for (final it in order)
        if (productOf[it.model] != null)
          _ShowcaseItem(productOf[it.model]!, reasonOf[it.model]),
    ];
    if (!mounted || widget.mode != mode) return;
    setState(() => _top = top);
  }

  Future<void> _openProduct(_ShowcaseItem entry) async {
    final product = entry.product;
    try {
      final engine =
          PersonalizationEngine(await SharedPreferences.getInstance());
      await engine.record(UserEvent(
        type: UserEventType.viewDetail,
        category: product.category,
        productName: product.name,
        price: product.price,
        at: DateTime.now(),
      ));
    } catch (_) {
      // Telemetri personalisasi gagal = diam saja.
    }
    if (!mounted) return;
    // Lembar detail produk: harga IDR + kartu konversi, lalu tombol
    // lanjut ke alur Cek Harga yang sudah ada.
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              MonexSpacing.screenPaddingH,
              4,
              MonexSpacing.screenPaddingH,
              24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                PriceConversionCard(priceIdr: product.price),
                const SizedBox(height: 12),
                MonexPrimaryButton(
                  label: AppStrings.priceCheckTitle,
                  icon: Icons.price_check,
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PriceCheckScreen(
                          initialQuery: product.name,
                          initialMode:
                              product.category == 'laptop' ? 'laptop' : 'pc',
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _iconFor(String category) => switch (category) {
        'cpu' => Icons.memory,
        'gpu' => Icons.videogame_asset_outlined,
        'motherboard' => Icons.dashboard_outlined,
        'ram' => Icons.sd_card_outlined,
        'storage' => Icons.storage,
        'laptop' => Icons.laptop,
        'pc' => Icons.desktop_windows_outlined,
        _ => Icons.widgets_outlined,
      };

  Widget _imageFor(NormalizedProduct product) {
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          _iconFor(product.category),
          size: 40,
          color: Theme.of(context).textTheme.bodySmall?.color,
        ),
      ),
    );
    final url = product.imageUrl;
    if (url == null) return placeholder;
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, _, _) => placeholder,
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : placeholder,
    );
  }

  Widget _card(_ShowcaseItem entry) {
    final theme = Theme.of(context);
    final product = entry.product;
    return MonexSurfaceCard(
      onTap: () => _openProduct(entry),
      padding: const EdgeInsets.all(10),
      radius: MonexSpacing.radiusMd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(MonexSpacing.radiusSm),
              child: _imageFor(product),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            product.name,
            style: theme.textTheme.titleSmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            formatRupiah(product.price),
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (entry.reason != null && entry.reason!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: MonexColors.limeMuted,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                entry.reason!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall,
              ),
            ),
          ],
        ],
      ),
    );
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
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: top.length,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            childAspectRatio: 0.72,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemBuilder: (_, i) => _card(top[i]),
        ),
      ],
    );
  }
}
