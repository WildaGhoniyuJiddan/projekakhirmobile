import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worthbang/services/app_database.dart';
import 'package:worthbang/services/sync_queue.dart';
import 'package:worthbang/services/sync_service.dart';

AppDatabase _memDb() => AppDatabase(NativeDatabase.memory());

SyncService _service(SyncQueue q) => SyncService(queue: q);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SyncQueue', () {
    test('enqueue → pending → remove → count', () async {
      final db = _memDb();
      addTearDown(db.close);
      final q = SyncQueue(db);

      expect(await q.count(), 0);
      await q.enqueue('feedback', {'rating': 5});
      await q.enqueue('wishlist', {'query': 'RTX 4060'});
      expect(await q.count(), 2);

      final items = await q.pending();
      expect(items.length, 2);
      expect(items.first.kind, 'feedback');

      await q.remove(items.first.id);
      expect(await q.count(), 1);
    });
  });

  group('SyncService.syncPending', () {
    test('antrean lawas dikuras → kosong', () async {
      SharedPreferences.setMockInitialValues({});
      final db = _memDb();
      addTearDown(db.close);
      final q = SyncQueue(db);
      final svc = _service(q);

      await q.enqueue('feedback',
          {'rating': 4, 'kesan': 'bagus', 'saran': '-'});
      await q.enqueue('wishlist',
          {'query': 'RTX 4060', 'mode': 'pc', 'target_price': 4000000});
      await q.enqueue('alert',
          {'query': 'RX 7600', 'mode': 'pc', 'target_price': 3500000});

      final rest = await svc.syncPending();
      expect(rest, 0);
      expect(await q.count(), 0);
    });

    test('last sync tercatat di SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final db = _memDb();
      addTearDown(db.close);
      final svc = _service(SyncQueue(db));

      await svc.syncPending();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(SyncService.lastSyncKey), isNotNull);
    });
  });
}
