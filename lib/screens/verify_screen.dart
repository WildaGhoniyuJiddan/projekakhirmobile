import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthbang/services/data/hash_chain_service.dart';
import 'package:worthbang/core/theme/monex_theme.dart';
import 'package:worthbang/core/widgets/monex_widgets.dart';
import 'package:worthbang/services/data/app_database.dart';
import 'package:worthbang/l10n/strings.dart';
import 'package:worthbang/screens/price_check_screen.dart';

/// Layar verifikasi hash chain: hitung ulang tiap blok, tandai yang rusak.
///
/// Termasuk self-test (debug): simulasi tampering in-memory untuk
/// mendemonstrasikan bahwa manipulasi data terdeteksi.
class VerifyScreen extends ConsumerStatefulWidget {
  const VerifyScreen({super.key});

  @override
  ConsumerState<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends ConsumerState<VerifyScreen> {
  List<HashVerificationResult>? _results;
  List<HistoryBlock> _blocks = [];
  bool _tamperedDemo = false;

  @override
  void initState() {
    super.initState();
    _verify();
  }

  Future<void> _verify() async {
    final repo = ref.read(historyRepositoryProvider);
    final results = await repo.verify();
    final blocks = await repo.latest(limit: 1000);
    if (mounted) {
      setState(() {
        _results = results;
        _blocks = blocks.reversed.toList(); // urut id menaik
        _tamperedDemo = false;
      });
    }
  }

  /// Self-test: ubah satu blok IN-MEMORY (DB tidak disentuh), verifikasi lagi.
  void _tamperSelfTest() {
    if (_blocks.isEmpty) return;
    final tampered = _blocks.map((b) {
      if (b.id == _blocks.first.id) {
        return HashBlock(
          id: b.id,
          timestampIso: b.createdAt.toIso8601String(),
          dataJson: '{"rusak":true}',
          prevHash: b.prevHash,
          hash: b.hash,
        );
      }
      return HashBlock(
        id: b.id,
        timestampIso: b.createdAt.toIso8601String(),
        dataJson: b.dataJson,
        prevHash: b.prevHash,
        hash: b.hash,
      );
    }).toList();
    setState(() {
      _results = HashChainService.verifyChain(tampered);
      _tamperedDemo = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final allOk = results != null &&
        results.isNotEmpty &&
        results.every((r) => r.ok);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.verifyTitle)),
      body: results == null
          ? const Center(child: MonexOrbitLoader(size: 56))
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                MonexSpacing.screenPaddingH,
                MonexSpacing.screenPaddingV,
                MonexSpacing.screenPaddingH,
                24,
              ),
              children: [
                MonexSurfaceCard(
                  color: results.isEmpty
                      ? null
                      : allOk
                          ? MonexColors.verdictGood.withValues(alpha: 0.12)
                          : MonexColors.danger.withValues(alpha: 0.12),
                  borderColor: results.isEmpty
                      ? null
                      : allOk
                          ? MonexColors.verdictGood.withValues(alpha: 0.4)
                          : MonexColors.danger.withValues(alpha: 0.4),
                  child: Row(
                    children: [
                      Icon(
                        results.isEmpty
                            ? Icons.info_outline
                            : allOk
                                ? Icons.verified
                                : Icons.warning_amber_rounded,
                        size: 32,
                        color: allOk
                            ? MonexColors.verdictGood
                            : results.isEmpty
                                ? null
                                : MonexColors.danger,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          results.isEmpty
                              ? AppStrings.verifyEmpty
                              : allOk
                                  ? AppStrings.verifyOk(results.length)
                                  : AppStrings.verifyFailed,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_tamperedDemo)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(AppStrings.tamperDemoNote),
                  ),
                const SizedBox(height: 12),
                for (final r in results)
                  Padding(
                    padding: const EdgeInsets.only(
                        bottom: MonexSpacing.gridGap),
                    child: MonexSurfaceCard(
                      padding: const EdgeInsets.all(
                          MonexSpacing.cardPaddingCompact),
                      radius: MonexSpacing.radiusMd,
                      child: MonexTransactionTile(
                        title: 'Blok #${r.block.id}',
                        subtitle:
                            'hash: ${r.block.hash.isEmpty ? '-' : r.block.hash.substring(0, 12)}…',
                        leadingIcon: r.ok
                            ? Icons.check_circle_outline
                            : Icons.cancel_outlined,
                        leadingColor: r.ok
                            ? MonexColors.verdictGood
                            : MonexColors.danger,
                        leadingBackground: r.ok
                            ? MonexColors.verdictGood.withValues(alpha: 0.14)
                            : MonexColors.danger.withValues(alpha: 0.14),
                        padding: EdgeInsets.zero,
                        trailing: Text(
                          r.ok ? 'VALID' : 'RUSAK',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: r.ok
                                ? MonexColors.verdictGood
                                : MonexColors.danger,
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                MonexSecondaryButton(
                  onPressed: _verify,
                  icon: Icons.refresh_rounded,
                  label: AppStrings.verifyChainButton,
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed:
                      _blocks.isEmpty ? null : _tamperSelfTest,
                  icon: const Icon(Icons.bug_report_outlined),
                  label: const Text(AppStrings.tamperSelfTest),
                ),
              ],
            ),
    );
  }
}
