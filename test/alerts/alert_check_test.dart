import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthbang/models/price_check_models.dart';
import 'package:worthbang/services/features/alert_check_service.dart';
import 'package:worthbang/services/features/alerts_api.dart';
import 'package:worthbang/services/data/app_database.dart' hide PriceAlert;
import 'package:worthbang/services/features/price_check_api.dart';

/// Stub PriceCheckApi: analyze() mengembalikan harga pasar stub.
/// Alerts sekarang dari Drift lokal.
class _StubPriceCheckApi extends PriceCheckApi {
  _StubPriceCheckApi({required this.marketPrice});

  int marketPrice;

  @override
  Future<AnalysisResult> analyze({
    required String mode,
    required String query,
    required int price,
    String? componentType,
    String condition = 'any',
  }) async {
    return AnalysisResult(
      mode: mode,
      query: query,
      inputPrice: price,
      score: 80,
      verdict: 'wajar',
      referencePrice: marketPrice,
    );
  }
}

class _FakeNotifier implements PriceAlertNotifier {
  final List<(int, String, int, int)> sent = [];

  @override
  Future<void> showPriceAlert({
    required int id,
    required String query,
    required int currentPrice,
    required int targetPrice,
  }) async {
    sent.add((id, query, currentPrice, targetPrice));
  }

  // implements = tanpa warisan implementasi default, jadi wajib ada.
  @override
  Future<void> schedulePriceAlert({
    required int id,
    required String query,
    required int currentPrice,
    required int targetPrice,
  }) =>
      showPriceAlert(
        id: id,
        query: query,
        currentPrice: currentPrice,
        targetPrice: targetPrice,
      );
}

class _FakeDedup implements AlertDedupStore {
  final Map<int, int> _m = {};

  @override
  Future<bool> wasNotified(int alertId, int price) async =>
      _m[alertId] == price;

  @override
  Future<void> markNotified(int alertId, int price) async =>
      _m[alertId] = price;

  @override
  Future<void> clear(int alertId) async => _m.remove(alertId);

  bool get hasEntry => _m.isNotEmpty;
}

/// DB memori dengan 2 alert: satu aktif (target 4.3jt), satu nonaktif.
Future<AppDatabase> _seedDb() async {
  final db = AppDatabase(NativeDatabase.memory());
  await db.into(db.priceAlerts).insert(PriceAlertsCompanion.insert(
        query: 'RTX 4060',
        mode: 'pc',
        targetPrice: 4300000,
      ));
  await db.into(db.priceAlerts).insert(PriceAlertsCompanion.insert(
        query: 'Ryzen 5 5600',
        mode: 'pc',
        targetPrice: 1500000,
        isActive: const Value(false),
      ));
  return db;
}

AlertCheckService _service(
  AppDatabase db,
  _StubPriceCheckApi api,
  _FakeNotifier notifier,
  _FakeDedup dedup,
) {
  return AlertCheckService(
    alertsApi: AlertsApi(db),
    priceCheckApi: api,
    notifier: notifier,
    dedup: dedup,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AlertCheckService.checkNow', () {
    test('harga ≤ target → notifikasi sekali (dedup)', () async {
      final db = await _seedDb();
      addTearDown(db.close);
      final client = _StubPriceCheckApi(marketPrice: 4200000);
      final notifier = _FakeNotifier();
      final dedup = _FakeDedup();
      final svc = _service(db, client, notifier, dedup);

      expect(await svc.checkNow(), 1);
      expect(notifier.sent.length, 1);
      expect(notifier.sent.first.$2, 'RTX 4060');

      // Cek kedua: harga sama → tidak notif lagi.
      expect(await svc.checkNow(), 0);
      expect(notifier.sent.length, 1);
    });

    test('harga > target → tidak notif, dedup direset', () async {
      final db = await _seedDb();
      addTearDown(db.close);
      final client = _StubPriceCheckApi(marketPrice: 4200000);
      final notifier = _FakeNotifier();
      final dedup = _FakeDedup();
      final svc = _service(db, client, notifier, dedup);

      expect(await svc.checkNow(), 1);
      expect(dedup.hasEntry, isTrue);

      // Harga naik di atas target → dedup dibersihkan.
      client.marketPrice = 4500000;
      expect(await svc.checkNow(), 0);
      expect(dedup.hasEntry, isFalse);

      // Harga turun lagi → notif ulang (1x).
      client.marketPrice = 4100000;
      expect(await svc.checkNow(), 1);
      expect(notifier.sent.length, 2);
    });

    test('alert nonaktif diabaikan', () async {
      final db = await _seedDb();
      addTearDown(db.close);
      final client = _StubPriceCheckApi(marketPrice: 1000000);
      final notifier = _FakeNotifier();
      final svc = _service(db, client, notifier, _FakeDedup());
      // Hanya alert aktif (target 4.3jt, pasar 1jt → terpicu).
      // Alert nonaktif meski pasar < target → tidak terpicu.
      expect(await svc.checkNow(), 1);
      expect(notifier.sent.map((e) => e.$1), [1]);
    });

    test('model PriceAlert.fromJson tetap parse', () {
      final a = PriceAlert.fromJson({
        'id': 5,
        'query': 'RTX 4060',
        'target_price': 4300000,
        'current_price': 4600000,
        'is_active': true,
      });
      expect(a.id, 5);
      expect(a.targetPrice, 4300000);
      expect(a.currentPrice, 4600000);
      expect(a.isActive, isTrue);
    });
  });

  group('AlertsApi lokal (Drift)', () {
    test('CRUD round-trip', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final api = AlertsApi(db);

      expect(await api.getAlerts(), isEmpty);

      final added = await api.addAlert(
        query: 'RTX 4060',
        mode: 'pc',
        targetPrice: 4300000,
      );
      expect(added.id, isNonZero);
      expect(added.query, 'RTX 4060');
      expect(added.isActive, isTrue);

      final list = await api.getAlerts();
      expect(list.length, 1);

      await api.deleteAlert(added.id);
      expect(await api.getAlerts(), isEmpty);
    });
  });
}
