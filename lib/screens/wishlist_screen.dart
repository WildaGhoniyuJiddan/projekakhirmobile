import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthbang/core/theme/monex_theme.dart';
import 'package:worthbang/core/widgets/monex_widgets.dart';
import 'package:worthbang/utils/rupiah.dart';
import 'package:worthbang/l10n/strings.dart';
import 'package:worthbang/services/core/notification_permissions.dart';
import 'package:worthbang/services/features/alert_check_service.dart';
import 'package:worthbang/services/features/alerts_api.dart';
import 'package:worthbang/services/features/wishlist_api.dart';

/// Persentase penurunan harga untuk simulasi (di rentang 10–15%).
const simulationDropPercent = 12;

/// Id notifikasi khusus simulasi fallback (di luar rentang id alert).
const simulationFallbackId = 990001;

/// Payload simulasi notifikasi: alert AKTIF pertama dengan harga
/// disimulasikan turun [simulationDropPercent]% di bawah targetnya.
/// Bila belum ada alert aktif, fallback ke produk contoh realistis.
({int id, String query, int currentPrice, int targetPrice})
    buildSimulationPayload(List<PriceAlert>? alerts) {
  final active = alerts?.where((a) => a.isActive).firstOrNull;
  if (active != null) {
    final dropped =
        (active.targetPrice * (100 - simulationDropPercent) / 100).round();
    return (
      id: active.id,
      query: active.query,
      currentPrice: dropped,
      targetPrice: active.targetPrice,
    );
  }
  const target = 5200000;
  return (
    id: simulationFallbackId,
    query: 'RTX 4060',
    currentPrice: (target * (100 - simulationDropPercent) / 100).round(),
    targetPrice: target,
  );
}

/// Layar gabungan Wishlist & Alert Harga (dua tab).
class WishlistAlertsScreen extends ConsumerStatefulWidget {
  const WishlistAlertsScreen({super.key});

  @override
  ConsumerState<WishlistAlertsScreen> createState() =>
      _WishlistAlertsScreenState();
}

class _WishlistAlertsScreenState
    extends ConsumerState<WishlistAlertsScreen> {
  List<WishlistItem>? _wishlist;
  List<PriceAlert>? _alerts;
  bool _checking = false;
  bool _simulating = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final w =
          await ref.read(wishlistApiProvider).getWishlist();
      final a = await ref.read(alertsApiProvider).getAlerts();
      if (mounted) {
        setState(() {
          _wishlist = w;
          _alerts = a;
        });
      }
    } catch (e) {
      if (mounted) {
        showMonexToast(context, e.toString(), isError: true);
      }
    }
  }

  Future<void> _deleteWishlist(int id) async {
    await ref.read(wishlistApiProvider).deleteWishlist(id);
    await _reload();
  }

  Future<void> _deleteAlert(int id) async {
    await ref.read(alertsApiProvider).deleteAlert(id);
    await _reload();
  }

  /// Cek alert manual — memicu [AlertCheckService] langsung.
  Future<void> _checkNow() async {
    setState(() => _checking = true);
    try {
      final service = await ref.read(alertCheckServiceProvider.future);
      final n = await service.checkNow();
      if (!mounted) return;
      showMonexToast(
        context,
        n > 0
            ? '$n alert terpicu — cek notifikasi.'
            : AppStrings.alertCheckNone,
        isSuccess: true,
      );
      await _reload();
    } catch (e) {
      if (mounted) {
        showMonexToast(context, e.toString(), isError: true);
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  /// Simulasi notifikasi price alert lewat jalur PRODUKSI
  /// ([PriceAlertNotifier.schedulePriceAlert]) — untuk demo/pengujian
  /// tanpa menunggu harga benar-benar turun.
  ///
  /// Dijadwalkan 3 detik lewat OS (bukan tampil langsung), supaya
  /// penguji sempat keluar dari aplikasi dan membuktikan notifikasi
  /// tetap muncul saat aplikasi tidak dibuka.
  ///
  /// Pre-flight WAJIB: status izin dicek real-time. Bila nonaktif,
  /// notifikasi DIBATALKAN dan pengguna diarahkan ke Pengaturan —
  /// tidak ada kegagalan diam-diam.
  Future<void> _simulateNotification() async {
    setState(() => _simulating = true);
    try {
      final perm =
          await ref.read(notificationPermissionServiceProvider.future);
      final enabled = await perm.isEnabled();
      if (!mounted) return;
      if (!enabled) {
        await _showPermissionBlockedDialog(perm);
        return;
      }
      final payload = buildSimulationPayload(_alerts);
      await ref.read(priceAlertNotifierProvider).schedulePriceAlert(
            id: payload.id,
            query: payload.query,
            currentPrice: payload.currentPrice,
            targetPrice: payload.targetPrice,
          );
      if (!mounted) return;
      showMonexToast(context, AppStrings.simulationScheduled,
          isSuccess: true);
    } catch (e) {
      if (mounted) {
        showMonexToast(context, e.toString(), isError: true);
      }
    } finally {
      if (mounted) setState(() => _simulating = false);
    }
  }

  Future<void> _showPermissionBlockedDialog(
      NotificationPermissionService perm) async {
    final open = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AppStrings.simulationBlockedTitle),
        content: const Text(AppStrings.simulationBlockedBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(AppStrings.laterButton),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(AppStrings.openSettingsButton),
          ),
        ],
      ),
    );
    if (open != true) return;
    final opened = await perm.openNotificationSettings();
    if (!opened && mounted) {
      showMonexToast(context, AppStrings.simulationSettingsFailed,
          isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(AppStrings.wishlistTitle),
          bottom: const TabBar(
            tabs: [
              Tab(
                text: AppStrings.wishlistTab,
                icon: Icon(Icons.favorite_outline),
              ),
              Tab(
                text: AppStrings.alertsTab,
                icon: Icon(Icons.notifications_outlined),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildWishlist(),
            _buildAlerts(),
          ],
        ),
      ),
    );
  }

  Widget _buildWishlist() {
    final wishlist = _wishlist;
    if (wishlist == null) {
      return const Center(child: MonexOrbitLoader(size: 56));
    }
    if (wishlist.isEmpty) {
      return const MonexEmptyState(
        icon: Icons.favorite_border_rounded,
        title: AppStrings.wishlistEmpty,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(MonexSpacing.screenPaddingH),
      itemCount: wishlist.length,
      itemBuilder: (context, i) {
        final w = wishlist[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: MonexSpacing.gridGap),
          child: MonexSurfaceCard(
            padding: const EdgeInsets.all(MonexSpacing.cardPaddingCompact),
            radius: MonexSpacing.radiusMd,
            child: MonexTransactionTile(
              title: w.query,
              subtitle: w.targetPrice != null
                  ? 'Target: ${formatRupiah(w.targetPrice!)}'
                  : 'Tanpa target harga',
              padding: EdgeInsets.zero,
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteWishlist(w.id),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAlerts() {
    final alerts = _alerts;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(MonexSpacing.screenPaddingH),
          child: MonexPrimaryButton(
            onPressed: _checking ? null : _checkNow,
            icon: Icons.refresh_rounded,
            label: AppStrings.checkAlertsNow,
            loading: _checking,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            MonexSpacing.screenPaddingH,
            0,
            MonexSpacing.screenPaddingH,
            MonexSpacing.screenPaddingH,
          ),
          child: MonexSecondaryButton(
            onPressed: _simulating ? null : _simulateNotification,
            icon: Icons.notifications_active_outlined,
            label: AppStrings.simulateNotification,
          ),
        ),
        Expanded(
          child: alerts == null
              ? const Center(child: MonexOrbitLoader(size: 56))
              : alerts.isEmpty
                  ? const MonexEmptyState(
                      icon: Icons.notifications_off_outlined,
                      title: AppStrings.alertsEmpty,
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        MonexSpacing.screenPaddingH,
                        0,
                        MonexSpacing.screenPaddingH,
                        24,
                      ),
                      itemCount: alerts.length,
                      itemBuilder: (context, i) {
                        final a = alerts[i];
                        final hit = a.currentPrice != null &&
                            a.currentPrice! <= a.targetPrice;
                        return Padding(
                          padding: const EdgeInsets.only(
                              bottom: MonexSpacing.gridGap),
                          child: MonexSurfaceCard(
                            padding: const EdgeInsets.all(
                                MonexSpacing.cardPaddingCompact),
                            radius: MonexSpacing.radiusMd,
                            child: MonexTransactionTile(
                              leadingIcon: hit
                                  ? Icons.notifications_active
                                  : Icons.notifications_outlined,
                              leadingColor:
                                  hit ? MonexColors.verdictGood : null,
                              title: a.query,
                              subtitle:
                                  'Target: ${formatRupiah(a.targetPrice)}'
                                  '${a.currentPrice != null ? ' • kini ${formatRupiah(a.currentPrice!)}' : ''}',
                              padding: EdgeInsets.zero,
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _deleteAlert(a.id),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
