import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:worthbang/core/theme/monex_theme.dart';
import 'package:worthbang/core/widgets/monex_widgets.dart';
import 'package:worthbang/utils/rupiah.dart';
import 'package:worthbang/widgets/price_conversion_card.dart';
import 'package:worthbang/widgets/verdict_badge.dart';
import 'package:worthbang/l10n/strings.dart';
import 'package:worthbang/l10n/dream_strings.dart';
import 'package:worthbang/services/features/alerts_api.dart';
import 'package:worthbang/services/features/dream_build_api.dart';
import 'package:worthbang/services/features/wishlist_api.dart';
import 'package:worthbang/services/features/personalization/personalization_engine.dart';
import 'package:worthbang/models/price_check_models.dart';

/// Layar hasil analisis: verdict, skor, rentang wajar, pembanding, alternatif.
///
/// Hasil sudah tersimpan sebagai blok hash chain (lihat [blockId]) saat layar
/// ini dibuka — diverifikasi di tab Riwayat (T6).
class ResultScreen extends ConsumerWidget {
  const ResultScreen({super.key, required this.result, required this.blockId});

  final AnalysisResult result;
  final int blockId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = result;
    final theme = Theme.of(context);
    final verdict = verdictFromString(r.verdict);

    return Scaffold(
      appBar: AppBar(
        title: Text(r.query, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.favorite_outline),
            tooltip: AppStrings.addWishlist,
            onPressed: () async {
              try {
                await ref.read(wishlistApiProvider).addWishlist(
                      query: r.query,
                      mode: r.mode,
                      targetPrice: r.inputPrice,
                    );
                if (context.mounted) {
                  showMonexToast(
                    context,
                    AppStrings.wishlistAdded,
                    isSuccess: true,
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  showMonexToast(context, e.toString(), isError: true);
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.notification_add_outlined),
            tooltip: AppStrings.addAlert,
            onPressed: () => _showAlertDialog(context, ref, r),
          ),
          IconButton(
            icon: const Icon(Icons.rocket_launch_outlined),
            tooltip: DreamStrings.addFromResult,
            onPressed: () => _showDreamDialog(context, ref, r),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          MonexSpacing.screenPaddingH,
          MonexSpacing.screenPaddingV,
          MonexSpacing.screenPaddingH,
          24,
        ),
        children: [
          // Hero: verdict + skor.
          MonexSurfaceCard(
            padding: const EdgeInsets.all(MonexSpacing.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: VerdictBadge(verdict: verdict),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Skor ${r.score.toStringAsFixed(0)}/100',
                      style: theme.textTheme.titleLarge,
                    ),
                  ],
                ),
                const SizedBox(height: MonexSpacing.sectionGap),
                MonexProgressBar(
                  value: r.score / 100,
                  color: AppThemeVerdictColor.of(verdict),
                ),
                const SizedBox(height: MonexSpacing.sectionGap),
                Text(
                  'Harga input: ${formatRupiah(r.inputPrice)}',
                  style: theme.textTheme.titleMedium,
                ),
                if (r.referencePrice != null)
                  Text(
                    'Median pasar: ${formatRupiah(r.referencePrice!)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                if (r.fairPriceLow != null && r.fairPriceHigh != null)
                  Text(
                    'Rentang wajar: ${formatRupiah(r.fairPriceLow!)} – ${formatRupiah(r.fairPriceHigh!)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                if (r.priceDeltaPercent != null)
                  Text(
                    'Selisih: ${r.priceDeltaPercent!.toStringAsFixed(1)}% dari median',
                    style: theme.textTheme.bodyMedium,
                  ),
              ],
            ),
          ),
          const SizedBox(height: MonexSpacing.sectionGap),
          PriceConversionCard(priceIdr: r.inputPrice),
          if (r.recommendation != null) ...[
            const SizedBox(height: MonexSpacing.sectionGap),
            MonexSurfaceCard(
              padding: const EdgeInsets.all(MonexSpacing.cardPaddingCompact),
              color: MonexColors.limeMuted,
              borderColor: MonexColors.lime.withValues(alpha: 0.35),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.tips_and_updates_outlined,
                      size: 18, color: MonexColors.lime),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      r.recommendation!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: MonexSpacing.sectionGap),
          Row(
            children: [
              Icon(Icons.link,
                  size: 16, color: theme.textTheme.bodySmall?.color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Tersimpan di riwayat (blok #$blockId, hash chain)',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          if (r.freshnessLabel != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.update,
                    size: 16, color: theme.textTheme.bodySmall?.color),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Data: ${r.freshnessLabel!}${r.isStale ? ' (basi)' : ''}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
          if (r.comparisons.isNotEmpty) ...[
            const SizedBox(height: MonexSpacing.sectionGap),
            Text(
              'Pembanding (${r.listingCount} listing)',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: MonexSpacing.gridGap),
            for (final c in r.comparisons)
              MonexSurfaceCard(
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.all(MonexSpacing.cardPaddingCompact),
                radius: MonexSpacing.radiusMd,
                child: MonexTransactionTile(
                  title: c.title,
                  subtitle:
                      '${c.source}${c.condition != null ? ' • ${c.condition}' : ''}',
                  padding: EdgeInsets.zero,
                  trailing: Text(
                    formatRupiah(c.price),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ),
          ],
          if (r.alternatives.isNotEmpty) ...[
            const SizedBox(height: MonexSpacing.sectionGap),
            Text(
              'Alternatif',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: MonexSpacing.gridGap),
            for (final a in r.alternatives)
              MonexSurfaceCard(
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.all(MonexSpacing.cardPaddingCompact),
                radius: MonexSpacing.radiusMd,
                child: MonexTransactionTile(
                  title: a.name,
                  subtitle: a.gainPercent != null
                      ? '+${a.gainPercent!.toStringAsFixed(0)}% performa'
                      : null,
                  padding: EdgeInsets.zero,
                  trailing: Text(
                    formatRupiah(a.estPriceIdr),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 24),
          MonexSecondaryButton(
            label: AppStrings.doneButton,
            icon: Icons.check_rounded,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// Pemetaan verdict → warna accent (lime untuk bagus, amber wajar, danger
/// kemahalan). Dipisah agar widget library tidak bergantung pada
/// `VerdictBadge` (dan sebaliknya).
class AppThemeVerdictColor {
  const AppThemeVerdictColor._();

  static Color of(Verdict verdict) => switch (verdict) {
        Verdict.good => MonexColors.verdictGood,
        Verdict.fair => MonexColors.verdictFair,
        Verdict.bad => MonexColors.verdictBad,
      };
}

/// Slot Rakitan Impian dari kategori/mode produk hasil analisis.
String _dreamSlotFor(AnalysisResult r) {
  final hay = '${r.mode} ${r.query}'.toLowerCase();
  bool has(List<String> keys) => keys.any(hay.contains);
  if (has(['gpu', 'vga', 'rtx', 'gtx', 'radeon', 'geforce'])) return 'GPU';
  if (has(['cpu', 'prosesor', 'processor', 'ryzen'])) return 'CPU';
  if (has(['motherboard', 'mobo', 'mainboard'])) return 'Motherboard';
  if (has(['ram', 'memori', 'memory', 'ddr'])) return 'RAM';
  if (has(['ssd', 'hdd', 'nvme', 'storage', 'harddisk'])) return 'Storage';
  if (has(['psu', 'power supply'])) return 'PSU';
  if (has(['casing', 'case'])) return 'Casing';
  if (has(['cooler', 'pendingin'])) return 'Cooler';
  if (has(['monitor', 'layar'])) return 'Monitor';
  return 'Lainnya';
}

// Event personalisasi (AI-Core): produk masuk Rakitan Impian adalah
// sinyal terkuat (bobot 5). Kategori sengaja tidak diisi — label slot
// ("CPU"/"Lainnya") beda kosakata dengan kategori katalog; mesin
// mendeteksi kategori dari nama produk. Best-effort: kegagalan
// mencatat tidak boleh mengganggu alur utama.
Future<void> _recordAddToDreamEvent(String partName, int price) async {
  try {
    final engine =
        PersonalizationEngine(await SharedPreferences.getInstance());
    await engine.record(UserEvent(
      type: UserEventType.addToDream,
      productName: partName,
      price: price,
      at: DateTime.now(),
    ));
  } catch (_) {
    // Telemetri personalisasi gagal = diam saja.
  }
}

/// Dialog tambah produk hasil analisis ke kartu Rakitan Impian:
/// pilih kartu yang ada atau buat baru.
Future<void> _showDreamDialog(
    BuildContext context, WidgetRef ref, AnalysisResult r) async {
  final api = ref.read(dreamBuildApiProvider);
  List<DreamBuild> builds;
  try {
    builds = await api.listBuilds();
  } catch (e) {
    if (context.mounted) {
      showMonexToast(context, e.toString(), isError: true);
    }
    return;
  }
  if (!context.mounted) return;
  final picked = await showDialog<DreamBuild?>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text(DreamStrings.addFromResultTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final b in builds)
              ListTile(
                title: Text(b.name),
                subtitle: Text(
                  '${b.isPublished ? DreamStrings.statusPublished : DreamStrings.statusDraft}'
                  ' • ${DreamStrings.versionLabel} ${b.version}',
                ),
                onTap: () => Navigator.of(context).pop(b),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text(DreamStrings.addFromResultNew),
              onTap: () => Navigator.of(context).pop(null),
            ),
          ],
        ),
      ),
    ),
  );
  if (!context.mounted) return;
  try {
    final item = DreamBuildItem(
      slot: _dreamSlotFor(r),
      partName: r.query,
      price: r.inputPrice,
    );
    final DreamBuild target;
    if (picked == null) {
      target = await api.createBuild(r.query);
      await api.saveDraft(
        build: target,
        name: target.name,
        items: [item],
      );
    } else {
      target = picked;
      await api.saveDraft(
        build: target,
        name: target.name,
        items: [...target.items, item],
      );
    }
    _recordAddToDreamEvent(r.query, r.inputPrice);
    if (context.mounted) {
      showMonexToast(context, DreamStrings.addedToast, isSuccess: true);
    }
  } catch (e) {
    if (context.mounted) {
      showMonexToast(context, e.toString(), isError: true);
    }
  }
}

/// Dialog buat price alert: input target harga → simpan lokal.
Future<void> _showAlertDialog(
    BuildContext context, WidgetRef ref, AnalysisResult r) async {
  final target = TextEditingController(
      text: r.referencePrice?.toString() ?? r.inputPrice.toString());
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text(AppStrings.addAlert),
      content: TextField(
        controller: target,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: AppStrings.targetPriceLabel,
          prefixText: 'Rp ',
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(AppStrings.cancelButton),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(AppStrings.saveButton),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final price =
      int.tryParse(target.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  if (price <= 0) return;
  try {
    await ref.read(alertsApiProvider).addAlert(
          query: r.query,
          mode: r.mode,
          targetPrice: price,
        );
    if (context.mounted) {
      showMonexToast(context, AppStrings.alertAdded, isSuccess: true);
    }
  } catch (e) {
    if (context.mounted) {
      showMonexToast(context, e.toString(), isError: true);
    }
  }
}
