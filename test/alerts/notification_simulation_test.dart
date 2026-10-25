import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worthbang/l10n/strings.dart';
import 'package:worthbang/providers/providers.dart';
import 'package:worthbang/screens/wishlist_screen.dart';
import 'package:worthbang/services/core/notification_permissions.dart';
import 'package:worthbang/services/data/app_database.dart' hide PriceAlert;
import 'package:worthbang/services/features/alert_check_service.dart';
import 'package:worthbang/services/features/alerts_api.dart';
import 'package:worthbang/utils/router.dart' show BottomNavShell;

/// Gateway fake: status izin dapat diatur, panggilan dicatat.
class _FakeGateway implements NotificationPermissionGateway {
  _FakeGateway({this.enabled, this.throwOnCheck = false});

  bool? enabled;
  bool throwOnCheck;

  /// Bila true, requestPermission() mengubah izin menjadi aktif
  /// (simulasi pengguna menekan Izinkan di popup sistem).
  bool grantOnRequest = false;
  int requestCount = 0;
  int settingsCount = 0;

  @override
  Future<bool?> areNotificationsEnabled() async {
    if (throwOnCheck) throw StateError('plugin error');
    return enabled;
  }

  @override
  Future<bool?> requestPermission() async {
    requestCount++;
    if (grantOnRequest) enabled = true;
    return enabled;
  }

  @override
  Future<void> openNotificationSettings() async {
    settingsCount++;
  }
}

/// Notifier fake: mencatat payload schedulePriceAlert dan showPriceAlert.
class _FakeNotifier implements PriceAlertNotifier {
  final List<(int, String, int, int)> scheduled = [];
  final List<(int, String, int, int)> sent = [];

  @override
  Future<void> schedulePriceAlert({
    required int id,
    required String query,
    required int currentPrice,
    required int targetPrice,
  }) async {
    scheduled.add((id, query, currentPrice, targetPrice));
  }

  @override
  Future<void> showPriceAlert({
    required int id,
    required String query,
    required int currentPrice,
    required int targetPrice,
  }) async {
    sent.add((id, query, currentPrice, targetPrice));
  }
}

Future<NotificationPermissionService> _service(
  _FakeGateway gateway,
  Map<String, Object> initialPrefs,
) async {
  SharedPreferences.setMockInitialValues(initialPrefs);
  final prefs = await SharedPreferences.getInstance();
  return NotificationPermissionService(gateway: gateway, prefs: prefs);
}

/// Router mini yang memasang BottomNavShell asli (4 branch kosong).
GoRouter _shellRouter() {
  StatefulShellBranch branch(String path) => StatefulShellBranch(
        routes: [
          GoRoute(
            path: path,
            builder: (_, _) => const Scaffold(body: Text('page')),
          ),
        ],
      );
  return GoRouter(
    initialLocation: '/home',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) =>
            BottomNavShell(navigationShell: shell),
        branches: [
          branch('/home'),
          branch('/search'),
          branch('/history'),
          branch('/profile'),
        ],
      ),
    ],
  );
}

/// DB memori berisi satu alert aktif RTX 4060 target Rp4,3 jt.
Future<AppDatabase> _seededDb() async {
  final db = AppDatabase(NativeDatabase.memory());
  await db.into(db.priceAlerts).insert(PriceAlertsCompanion.insert(
        query: 'RTX 4060',
        mode: 'pc',
        targetPrice: 4300000,
      ));
  return db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationPermissionService.ensurePromptedOnce', () {
    test('flag kosong + izin nonaktif → request tepat 1x, flag tersimpan',
        () async {
      final gateway = _FakeGateway(enabled: false);
      final svc = await _service(gateway, {});

      await svc.ensurePromptedOnce();
      // Panggilan berikutnya (rebuild/frame lain) tidak meminta lagi.
      await svc.ensurePromptedOnce();
      expect(gateway.requestCount, 1);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool(NotificationPermissionService.promptedKey),
        isTrue,
      );
    });

    test('flag sudah true → tidak pernah request lagi', () async {
      final gateway = _FakeGateway(enabled: false);
      final svc = await _service(gateway, {
        NotificationPermissionService.promptedKey: true,
      });

      await svc.ensurePromptedOnce();
      expect(gateway.requestCount, 0);
    });

    test('izin sudah aktif → tidak request, flag ditandai selesai',
        () async {
      final gateway = _FakeGateway(enabled: true);
      final svc = await _service(gateway, {});

      await svc.ensurePromptedOnce();
      expect(gateway.requestCount, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool(NotificationPermissionService.promptedKey),
        isTrue,
      );
    });

    test('gateway error → tidak crash, tidak request', () async {
      final gateway = _FakeGateway(enabled: false, throwOnCheck: true);
      final svc = await _service(gateway, {});

      await svc.ensurePromptedOnce(); // tidak boleh melempar
      expect(gateway.requestCount, 0);
    });
  });

  group('BottomNavShell: prompt izin frame pertama pasca-login', () {
    testWidgets('izin diminta tepat 1x saat flag lokal belum ada',
        (tester) async {
      final gateway = _FakeGateway(enabled: false);
      final svc = await _service(gateway, {});

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationPermissionServiceProvider
                .overrideWith((ref) async => svc),
          ],
          child: MaterialApp.router(routerConfig: _shellRouter()),
        ),
      );
      // Frame pertama + post-frame callback + rantai async izin.
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(gateway.requestCount, 1);

      // Frame-frame berikutnya tidak memicu permintaan ulang.
      await tester.pump();
      await tester.pump();
      expect(gateway.requestCount, 1);
    });

    testWidgets('sesi berikut (flag true) → izin tidak diminta ulang',
        (tester) async {
      final gateway = _FakeGateway(enabled: false);
      final svc = await _service(gateway, {
        NotificationPermissionService.promptedKey: true,
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationPermissionServiceProvider
                .overrideWith((ref) async => svc),
          ],
          child: MaterialApp.router(routerConfig: _shellRouter()),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(gateway.requestCount, 0);
    });
  });

  group('buildSimulationPayload', () {
    test('alert aktif pertama dipakai, harga turun 12% dari target', () {
      const alerts = [
        PriceAlert(
          id: 7,
          query: 'Ryzen 5 5600',
          targetPrice: 1500000,
          isActive: false,
        ),
        PriceAlert(id: 3, query: 'RTX 4060', targetPrice: 4300000),
      ];
      final p = buildSimulationPayload(alerts);
      expect(p.id, 3);
      expect(p.query, 'RTX 4060');
      expect(p.targetPrice, 4300000);
      expect(p.currentPrice, 3784000);
      expect(p.currentPrice, lessThan(p.targetPrice));
    });

    test('tanpa alert aktif → fallback produk contoh', () {
      final p = buildSimulationPayload(null);
      expect(p.id, simulationFallbackId);
      expect(p.query, 'RTX 4060');
      expect(p.targetPrice, 5200000);
      expect(p.currentPrice, 4576000);
    });
  });

  group('Tombol Simulasi Notifikasi (WishlistAlertsScreen)', () {
    Future<void> pumpScreen(
      WidgetTester tester, {
      required AppDatabase db,
      required NotificationPermissionService svc,
      required _FakeNotifier notifier,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            notificationPermissionServiceProvider
                .overrideWith((ref) async => svc),
            priceAlertNotifierProvider.overrideWithValue(notifier),
          ],
          child: const MaterialApp(home: WishlistAlertsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      // Pindah ke tab Alert Harga (tombol simulasi ada di sana).
      await tester.tap(find.text(AppStrings.alertsTab));
      await tester.pumpAndSettle();
    }

    testWidgets('izin aktif → schedulePriceAlert terpicu payload harga turun',
        (tester) async {
      final db = await _seededDb();
      addTearDown(db.close);
      final gateway = _FakeGateway(enabled: true);
      final svc = await _service(gateway, {});
      final notifier = _FakeNotifier();

      await pumpScreen(tester, db: db, svc: svc, notifier: notifier);
      await tester.tap(find.text(AppStrings.simulateNotification));
      await tester.pumpAndSettle();

      // Demo kini menjadwalkan (3 detik), bukan tampil langsung.
      expect(notifier.scheduled, hasLength(1));
      expect(notifier.sent, isEmpty);
      final (_, query, current, target) = notifier.scheduled.single;
      expect(query, 'RTX 4060');
      expect(target, 4300000);
      expect(current, 3784000);
      expect(current, lessThan(target));
      // Tidak ada dialog pemblokiran.
      expect(find.text(AppStrings.simulationBlockedTitle), findsNothing);
    });

    testWidgets(
        'izin ditolak → popup izin dimunculkan dulu, tetap ditolak → dialog Buka Pengaturan tampil',
        (tester) async {
      final db = await _seededDb();
      addTearDown(db.close);
      final gateway = _FakeGateway(enabled: false);
      final svc = await _service(gateway, {});
      final notifier = _FakeNotifier();

      await pumpScreen(tester, db: db, svc: svc, notifier: notifier);
      await tester.tap(find.text(AppStrings.simulateNotification));
      await tester.pumpAndSettle();

      // Popup sistem sempat dimunculkan (1x) sebelum dialog fallback.
      expect(gateway.requestCount, 1);
      expect(notifier.scheduled, isEmpty);
      expect(notifier.sent, isEmpty);
      expect(find.text(AppStrings.simulationBlockedTitle), findsOneWidget);
      expect(find.text(AppStrings.openSettingsButton), findsOneWidget);

      // Aksi Buka Pengaturan benar-benar memanggil gateway.
      await tester.tap(find.text(AppStrings.openSettingsButton));
      await tester.pumpAndSettle();
      expect(gateway.settingsCount, 1);
      expect(find.text(AppStrings.simulationBlockedTitle), findsNothing);
    });

    testWidgets(
        'izin nonaktif → popup izin diizinkan → notifikasi terjadwal, tanpa dialog',
        (tester) async {
      final db = await _seededDb();
      addTearDown(db.close);
      final gateway = _FakeGateway(enabled: false)..grantOnRequest = true;
      final svc = await _service(gateway, {});
      final notifier = _FakeNotifier();

      await pumpScreen(tester, db: db, svc: svc, notifier: notifier);
      await tester.tap(find.text(AppStrings.simulateNotification));
      await tester.pumpAndSettle();

      expect(gateway.requestCount, 1);
      expect(notifier.scheduled, hasLength(1));
      expect(find.text(AppStrings.simulationBlockedTitle), findsNothing);
    });
  });
}
