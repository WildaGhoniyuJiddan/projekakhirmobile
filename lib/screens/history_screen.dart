import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:worthbang/services/data/app_database.dart';
import 'package:worthbang/core/theme/monex_theme.dart';
import 'package:worthbang/core/widgets/monex_widgets.dart';
import 'package:worthbang/utils/rupiah.dart';
import 'package:worthbang/widgets/verdict_badge.dart';
import 'package:worthbang/l10n/strings.dart';
import 'package:worthbang/models/price_check_models.dart';
import 'package:worthbang/screens/price_check_screen.dart';
import 'package:worthbang/services/data/sync_queue.dart';
import 'package:worthbang/services/data/sync_service.dart';
import 'verify_screen.dart';

/// Tab Riwayat: daftar analisis tersimpan (offline-first, Drift) + verifikasi.
class HistoryListScreen extends ConsumerStatefulWidget {
  const HistoryListScreen({super.key});

  @override
  ConsumerState<HistoryListScreen> createState() =>
      _HistoryListScreenState();
}

class _HistoryListScreenState extends ConsumerState<HistoryListScreen> {
  List<HistoryBlock> _blocks = [];
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final blocks =
          await ref.read(historyRepositoryProvider).latest();
      if (!mounted) return;
      setState(() {
        _blocks = blocks;
        _loading = false;
      });
    } catch (_) {
      // DB lokal gagal dibaca — tampilkan list kosong, bukan spinner abadi.
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final sent =
          await ref.read(historyRepositoryProvider).syncToServer();
      final rest =
          await ref.read(syncServiceProvider).syncPending();
      ref.invalidate(pendingCountProvider);
      ref.invalidate(lastSyncAtProvider);
      if (!mounted) return;
      showMonexToast(context, AppStrings.syncHistoryDone(sent, rest),
          isSuccess: true);
    } catch (e) {
      if (!mounted) return;
      showMonexToast(context, e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.historyScreenTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.verified_outlined),
            tooltip: AppStrings.verifyChainButton,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const VerifyScreen()),
            ),
          ),
          IconButton(
            icon: _syncing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload_outlined),
            tooltip: AppStrings.syncButton,
            onPressed: _syncing ? null : _sync,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: MonexOrbitLoader(size: 56))
          : _blocks.isEmpty
              ? const MonexEmptyState(
                  icon: Icons.history_toggle_off_rounded,
                  title: AppStrings.historyEmpty,
                )
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      MonexSpacing.screenPaddingH,
                      MonexSpacing.screenPaddingV,
                      MonexSpacing.screenPaddingH,
                      24,
                    ),
                    itemCount: _blocks.length + 1,
                    itemBuilder: (context, i) {
                      if (i == 0) return const _LastSyncHeader();
                      final b = _blocks[i - 1];
                      return Padding(
                        padding: const EdgeInsets.only(
                            bottom: MonexSpacing.gridGap),
                        child: MonexSurfaceCard(
                          padding: const EdgeInsets.all(
                              MonexSpacing.cardPaddingCompact),
                          radius: MonexSpacing.radiusMd,
                          child: MonexTransactionTile(
                            title: b.query,
                            subtitle:
                              '${DateFormat('d MMM yyyy HH:mm', 'id_ID').format(b.createdAt.toLocal())}'
                              ' • blok #${b.id}'
                              '${b.hash.isEmpty ? ' (legacy)' : ''}',
                            padding: EdgeInsets.zero,
                            trailing: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                VerdictBadge(
                                    verdict:
                                        verdictFromString(b.verdict)),
                                const SizedBox(height: 4),
                                Text(formatRupiah(b.inputPrice),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall),
                              ],
                            ),
                            onTap: () =>
                                Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const VerifyScreen()),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

/// Baris "Terakhir diperbarui" (T15): waktu sinkron sukses terakhir.
class _LastSyncHeader extends ConsumerWidget {
  const _LastSyncHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastSync = ref.watch(lastSyncAtProvider).value;
    final text = lastSync == null
        ? AppStrings.neverSynced
        : AppStrings.lastUpdated(
            DateFormat('d MMM yyyy HH:mm', 'id_ID')
                .format(lastSync.toLocal()));
    return Padding(
      padding:
          const EdgeInsets.only(bottom: MonexSpacing.gridGap),
      child: Row(
        children: [
          const Icon(Icons.cloud_done_outlined, size: 14),
          const SizedBox(width: 6),
          Text(text,
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
