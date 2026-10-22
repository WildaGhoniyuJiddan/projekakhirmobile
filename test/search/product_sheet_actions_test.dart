import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:worthbang/core/widgets/monex_widgets.dart';
import 'package:worthbang/providers/providers.dart';
import 'package:worthbang/screens/search_screen.dart';
import 'package:worthbang/services/data/app_database.dart';
import 'package:worthbang/services/data/products_catalog.dart';
import 'package:worthbang/services/features/wishlist_api.dart';
import 'package:worthbang/widgets/price_conversion_card.dart';

/// Test lembar detail produk (ketuk kartu etalase): tiga tombol aksi
/// (Wishlist / Alert Harga / Rakitan Impian) + toggle wishlist memakai
/// API asli di atas database Drift in-memory.
void main() {
  late AppDatabase db;

  setUp(() {
    // Onboarding dianggap sudah diisi agar gerbangnya tidak membuka
    // layar onboarding di atas menu Cari.
    SharedPreferences.setMockInitialValues({
      'wb_onboarding_v1': jsonEncode({
        'need': 'gaming',
        'budgetMin': 5000000,
        'budgetMax': 15000000,
        'platform': 'amd_am5',
      }),
    });
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    // Panaskan cache statik ProductsCatalog di zona async nyata:
    // pemuatan aset yang dimulai dari initState tidak selesai di
    // zona fake-async test, jadi etalase akan kosong tanpa ini.
    await tester.runAsync(ProductsCatalog.load);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SearchFilterScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openFirstProductSheet(WidgetTester tester) async {
    final cards = find.byType(MonexSurfaceCard);
    expect(cards, findsWidgets);
    await tester.tap(cards.first);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
  }

  testWidgets('Lembar produk memuat kartu konversi + tiga tombol aksi',
      (tester) async {
    await pumpScreen(tester);
    await openFirstProductSheet(tester);

    expect(find.byType(PriceConversionCard), findsOneWidget);
    expect(find.text('Wishlist'), findsOneWidget);
    expect(find.text('Alert Harga'), findsOneWidget);
    expect(find.text('Rakitan Impian'), findsOneWidget);
    expect(find.text('Cek Harga'), findsOneWidget);
  });

  testWidgets('Ketuk Wishlist menyimpan, ketuk lagi menghapus (toggle)',
      (tester) async {
    await pumpScreen(tester);
    await openFirstProductSheet(tester);

    await tester.tap(find.text('Wishlist'));
    await tester.pumpAndSettle();

    final saved = await WishlistApi(db).getWishlist();
    expect(saved, hasLength(1));
    expect(saved.single.query, isNotEmpty);
    expect(saved.single.targetPrice, isNotNull);
    expect(find.text('Di Wishlist'), findsOneWidget);

    await tester.tap(find.text('Di Wishlist'));
    await tester.pumpAndSettle();

    expect(await WishlistApi(db).getWishlist(), isEmpty);
    expect(find.text('Wishlist'), findsOneWidget);
  });

  testWidgets('Lembar produk pada lebar 320px tanpa overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpScreen(tester);
    await openFirstProductSheet(tester);

    expect(find.text('Wishlist'), findsOneWidget);
    expect(find.text('Alert Harga'), findsOneWidget);
    expect(find.text('Rakitan Impian'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
