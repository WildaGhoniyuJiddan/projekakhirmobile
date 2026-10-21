import 'dart:io';

import 'package:drift/drift.dart' show LazyDatabase;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:worthbang/services/core/api_client.dart';
import 'package:worthbang/services/core/dio_api_client.dart';
import 'package:worthbang/services/auth/token_storage.dart';
import 'package:worthbang/services/data/app_database.dart';

/// Penyimpanan token aman (flutter_secure_storage).
final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

/// HTTP client — ganti ke [FakeApiClient] untuk demo tanpa backend:
/// `apiClientProvider.overrideWithValue(FakeApiClient())`.
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = DioApiClient(tokenStorage: ref.watch(tokenStorageProvider));
  ref.onDispose(client.close);
  return client;
});

/// Database lokal Drift (SQLite file persisten, T15).
/// Riwayat, wishlist, alert, & antrian mutasi bertahan antar sesi.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'worthbang.sqlite'));
    return NativeDatabase.createInBackground(file);
  }));
  ref.onDispose(db.close);
  return db;
});
