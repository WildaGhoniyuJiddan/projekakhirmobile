import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthbang/utils/app.dart';
import 'package:worthbang/providers/providers.dart';
import 'package:worthbang/services/data/app_database.dart';
import 'package:worthbang/models/auth_models.dart';
import 'package:worthbang/providers/auth_controller.dart';
import 'package:worthbang/l10n/strings.dart';
import 'package:worthbang/widgets/app_logo.dart';

/// Stub auth: langsung authenticated agar guard router tidak redirect ke /login.
class _FakeAuthController extends AuthController {
  @override
  AuthState build() => const AuthState(
    status: AuthStatus.authenticated,
    user: AppUser(id: '1', name: 'Dan', email: 'dan@example.com'),
  );
}

/// Widget test bottom-nav shell (T0):
/// - 4 tab tampil dengan label Bahasa Indonesia.
/// - Tap tiap tab menampilkan konten yang sesuai.
///
/// Catatan: teks label tab juga dipakai sebagai judul AppBar placeholder,
/// jadi tap dilakukan lewat [NavigationDestination], bukan [find.text].
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
    expect(navLabel(AppStrings.tabHistory), findsOneWidget);
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

    // Pindah ke tab Riwayat.
    await tester.tap(navDestination(2));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.historyScreenTitle), findsOneWidget);

    // Pindah ke tab Profil: konten profil (bukan placeholder) tampil.
    await tester.tap(navDestination(3));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.settingsSection), findsOneWidget);
    expect(find.text(AppStrings.feedbackSection), findsOneWidget);

    // Kembali ke Beranda.
    await tester.tap(navDestination(0));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.homeGreeting), findsOneWidget);
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
