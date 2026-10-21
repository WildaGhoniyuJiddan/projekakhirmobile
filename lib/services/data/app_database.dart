import 'package:drift/drift.dart';

part 'app_database.g.dart';

/// Blok riwayat analisis harga (sumber tampilan Riwayat + verifikasi).
class HistoryBlocks extends Table {
  IntColumn get id => integer().autoIncrement()();
  // 'pc' | 'laptop' | 'bundle'
  TextColumn get mode => text()();
  TextColumn get query => text()();
  // Harga integer IDR (sesuai API_CONTRACT).
  IntColumn get inputPrice => integer()();
  RealColumn get score => real()();
  TextColumn get verdict => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // --- Hash chain (T3): rantai tamper-evident. Kolom non-null dengan default
  // '' agar migrasi dari schema v1 aman; blok lama dianggap "legacy".
  TextColumn get dataJson => text().withDefault(const Constant(''))();
  TextColumn get prevHash => text().withDefault(const Constant(''))();
  TextColumn get hash => text().withDefault(const Constant(''))();
}

/// Item wishlist user.
class WishlistItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get query => text()();
  TextColumn get mode => text()();
  IntColumn get targetPrice => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Alert harga: notifikasi saat harga <= target.
class PriceAlerts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get query => text()();
  TextColumn get mode => text()();
  IntColumn get targetPrice => integer()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Cache hasil API (mis. suggest, trend) dengan TTL sederhana.
class CachedResults extends Table {
  TextColumn get key => text()();
  // Payload JSON mentah.
  TextColumn get payload => text()();
  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {key};
}

/// Antrian mutasi offline (T15): aksi yang gagal karena jaringan,
/// dikirim ulang saat online. kind: 'feedback' | 'wishlist' | 'alert'.
class PendingMutations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get kind => text()();
  // Payload JSON sesuai kontrak endpoint tujuan.
  TextColumn get payload => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Akun lokal sementara sampai autentikasi backend tersedia.
class LocalAccounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get email => text().unique()();
  TextColumn get passwordSalt => text()();
  TextColumn get passwordHash => text()();
}

@DriftDatabase(
  tables: [
    HistoryBlocks,
    WishlistItems,
    PriceAlerts,
    CachedResults,
    PendingMutations,
    LocalAccounts,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(historyBlocks, historyBlocks.dataJson);
            await m.addColumn(historyBlocks, historyBlocks.prevHash);
            await m.addColumn(historyBlocks, historyBlocks.hash);
          }
          if (from < 3) {
            await m.createTable(pendingMutations);
          }
          if (from < 4) {
            await m.createTable(localAccounts);
          }
        },
      );
}
