import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthbang/utils/rupiah.dart';
import 'package:worthbang/core/theme/monex_theme.dart';
import 'package:worthbang/core/widgets/monex_widgets.dart';
import 'package:worthbang/widgets/verdict_badge.dart';
import 'package:worthbang/l10n/strings.dart';
import 'package:worthbang/models/bundle_models.dart';
import 'package:worthbang/models/price_check_models.dart';
import 'price_check_screen.dart';

/// Layar cek bundle: 1–6 komponen + harga paket, verdict per-komponen & total.
class BundleScreen extends ConsumerStatefulWidget {
  const BundleScreen({super.key});

  @override
  ConsumerState<BundleScreen> createState() => _BundleScreenState();
}

class _BundleItemField {
  final query = TextEditingController();
  final price = TextEditingController();
  void dispose() {
    query.dispose();
    price.dispose();
  }
}

class _BundleScreenState extends ConsumerState<BundleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _bundlePrice = TextEditingController();
  final _items = <_BundleItemField>[_BundleItemField(), _BundleItemField()];

  bool _loading = false;
  String? _error;
  BundleResult? _result;

  @override
  void dispose() {
    for (final i in _items) {
      i.dispose();
    }
    _bundlePrice.dispose();
    super.dispose();
  }

  int _itemPrice(_BundleItemField i) =>
      int.tryParse(i.price.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  int get _runningTotal => _items.fold(0, (s, i) => s + _itemPrice(i));

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final result =
          await ref.read(priceCheckApiProvider).analyzeBundle(
                items: [
                  for (final i in _items)
                    BundleInputItem(
                      query: i.query.text.trim(),
                      price: _itemPrice(i),
                    ),
                ],
                bundlePrice: int.parse(
                  _bundlePrice.text.replaceAll(RegExp(r'[^0-9]'), ''),
                ),
              );
      setState(() => _result = result);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.bundleTitle)),
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
                for (var idx = 0; idx < _items.length; idx++)
                  _ItemRow(
                    index: idx,
                    field: _items[idx],
                    canRemove: _items.length > 1,
                    onRemove: () => setState(() {
                      _items[idx].dispose();
                      _items.removeAt(idx);
                    }),
                    onChanged: () => setState(() {}),
                  ),
                if (_items.length < 6)
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _items.add(_BundleItemField())),
                    icon: const Icon(Icons.add),
                    label: const Text(AppStrings.bundleAddItem),
                  ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _bundlePrice,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: AppStrings.bundlePriceLabel,
                    prefixText: 'Rp ',
                    prefixIcon: Icon(Icons.shopping_bag_outlined),
                  ),
                  validator: (v) =>
                      (int.tryParse(v?.replaceAll(RegExp(r'[^0-9]'), '') ?? '') ??
                                  0) <=
                              0
                          ? AppStrings.priceInvalid
                          : null,
                ),
                const SizedBox(height: 8),
                Text(
                  'Total komponen: ${formatRupiah(_runningTotal)}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: MonexSpacing.sectionGap),
                MonexPrimaryButton(
                  onPressed: _loading ? null : _submit,
                  icon: Icons.analytics_outlined,
                  label: AppStrings.checkButton,
                  loading: _loading,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ],
                if (result != null) ...[
                  const SizedBox(height: MonexSpacing.sectionGap),
                  MonexSurfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: VerdictBadge(
                                  verdict: verdictFromString(result.verdict)),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Skor ${result.score.toStringAsFixed(0)}/100',
                              style:
                                  Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                        const SizedBox(height: MonexSpacing.gridGap),
                        MonexProgressBar(value: result.score / 100),
                        const SizedBox(height: MonexSpacing.gridGap),
                        Text(
                            'Harga paket: ${formatRupiah(result.bundlePrice)}',
                            style: Theme.of(context).textTheme.titleMedium),
                        if (result.referenceTotal != null)
                          Text(
                              'Total referensi: ${formatRupiah(result.referenceTotal!)}',
                              style: Theme.of(context).textTheme.bodyMedium),
                        if (result.savingsPercent != null)
                          Text(
                            'Hemat: ${result.savingsPercent!.toStringAsFixed(1)}%',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: MonexColors.verdictGood,
                                ),
                          ),
                      ],
                    ),
                  ),
                  if (result.recommendation != null) ...[
                    const SizedBox(height: MonexSpacing.gridGap),
                    MonexSurfaceCard(
                      color: MonexColors.limeMuted,
                      borderColor:
                          MonexColors.lime.withValues(alpha: 0.35),
                      radius: MonexSpacing.radiusMd,
                      padding: const EdgeInsets.all(
                          MonexSpacing.cardPaddingCompact),
                      child: Text(
                        result.recommendation!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                  if (result.items.isNotEmpty) ...[
                    const SizedBox(height: MonexSpacing.sectionGap),
                    Text('Per komponen',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: MonexSpacing.gridGap),
                    for (final item in result.items)
                      Padding(
                        padding:
                            const EdgeInsets.only(bottom: MonexSpacing.gridGap),
                        child: MonexSurfaceCard(
                          padding: const EdgeInsets.all(
                              MonexSpacing.cardPaddingCompact),
                          radius: MonexSpacing.radiusMd,
                          child: MonexTransactionTile(
                            title: item.query,
                            subtitle: item.verdict,
                            padding: EdgeInsets.zero,
                            trailing: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(formatRupiah(item.price),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall),
                                if (item.referencePrice != null)
                                  Text(
                                    'ref: ${formatRupiah(item.referencePrice!)}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.index,
    required this.field,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
  });

  final int index;
  final _BundleItemField field;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: field.query,
              decoration: InputDecoration(
                labelText: '${AppStrings.bundleItemLabel} ${index + 1}',
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? AppStrings.queryMin
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: field.price,
              keyboardType: TextInputType.number,
              onChanged: (_) => onChanged(),
              decoration: const InputDecoration(
                labelText: AppStrings.priceLabel,
                prefixText: 'Rp ',
              ),
              validator: (v) =>
                  (int.tryParse(
                              v?.replaceAll(RegExp(r'[^0-9]'), '') ?? '') ??
                          0) <=
                          0
                      ? AppStrings.priceInvalid
                      : null,
            ),
          ),
          if (canRemove)
          Padding(
          padding: const EdgeInsets.only(left: 4),
          child: IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: onRemove,
          ),
          ),
        ],
      ),
    );
  }
}
