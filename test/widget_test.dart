import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:worthbang/utils/app.dart';
import 'package:worthbang/providers/providers.dart';
import 'package:worthbang/services/data/app_database.dart';
import 'package:worthbang/models/auth_models.dart';
import 'package:worthbang/providers/auth_controller.dart';
import 'package:worthbang/l10n/strings.dart';
import 'package:worthbang/services/features/scan_price_service.dart';
import 'package:worthbang/widgets/app_logo.dart';

/// Stub auth: langsung authenticated agar guard router tidak redirect ke /login.
class _FakeAuthController extends AuthController {
  @override
  AuthState build() => const AuthState(
    status: AuthStatus.authenticated,
    user: AppUser(id: '1', name: 'Dan', email: 'dan@example.com'),
  );
}

class _FakeScanService implements IScanPriceService {
  @override
  Future<ScanServiceResult> captureAndParse({
    ImageSource source = ImageSource.camera,
  }) async =>
      ScanServiceResult.cancelled();

  @override
  Future<String> recognizeTextFromFile(File imageFile) async => '';

  @override
  Future<void> dispose() async {}
}

/// Widget test bottom-nav shell:
/// - 4 tab tampil dengan label Bahasa Indonesia (Beranda, Cari, Pindai Harga, Profil).
/// - Tap tiap tab menampilkan konten yang sesuai.
/// - Riwayat Analisis dapat diakses dari top bar Beranda.
void main() {
  Finder navDestination(int index) =>
      find.byType(NavigationDestination).at(index);

  Finder navLabel(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  // DB file persisten (path_provider) tidak ada di widget test —
  // pakai in-memory agar hermetic.
  final memDb = AppDatabase(NativeDatabase.memory());

  ProviderScope app() => ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(_FakeAuthController.new),
      databaseProvider.overrideWithValue(memDb),
      scanPriceServiceProvider.overrideWithValue(_FakeScanService()),
    ],
    child: const WorthBangApp(),
  );

  testWidgets('BottomNavShell menampilkan 4 tab dan berpindah tab', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // Empat label tab dalam Bahasa Indonesia ada di NavigationBar.
    expect(navLabel(AppStrings.tabHome), findsOneWidget);
    expect(navLabel(AppStrings.tabSearch), findsOneWidget);
    expect(navLabel(AppStrings.tabScanPrice), findsOneWidget);
    expect(navLabel(AppStrings.tabProfile), findsOneWidget);

    // Tab awal: Beranda menampilkan dashboard fitur.
    expect(find.text(AppStrings.homeGreeting), findsOneWidget);
    expect(find.text(AppStrings.priceCheckTitle), findsOneWidget);
    expect(find.text(AppStrings.homeExploreTitle), findsOneWidget);
    expect(find.byType(AppLogo), findsOneWidget);

    // Pindah ke tab Cari.
    await tester.tap(navDestination(1));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.searchScreenTitle), findsOneWidget);

    // Pindah ke tab Pindai Harga.
    await tester.tap(navDestination(2));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.scanGuideTitle), findsOneWidget);

    // Pindah ke tab Profil: konten profil (bukan placeholder) tampil.
    await tester.tap(navDestination(3));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.settingsSection), findsOneWidget);
    expect(find.text(AppStrings.feedbackSection), findsOneWidget);

    // Kembali ke Beranda.
    await tester.tap(navDestination(0));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.homeGreeting), findsOneWidget);

    // Top bar Beranda: tombol riwayat membuka Riwayat Analisis.
    await tester.tap(find.byTooltip(AppStrings.historyScreenTitle));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.historyScreenTitle), findsOneWidget);
  });

  testWidgets('NavigationBar punya tepat 4 destination', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
  });
}
