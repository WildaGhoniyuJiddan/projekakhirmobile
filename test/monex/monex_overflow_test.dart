import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:worthbang/core/theme/monex_theme.dart';
import 'package:worthbang/core/widgets/monex_widgets.dart';
import 'package:worthbang/l10n/strings.dart';
import 'package:worthbang/models/auth_models.dart';
import 'package:worthbang/providers/auth_controller.dart';
import 'package:worthbang/providers/providers.dart';
import 'package:worthbang/screens/bundle_screen.dart';
import 'package:worthbang/screens/builder_screen.dart';
import 'package:worthbang/screens/chat_screen.dart';
import 'package:worthbang/screens/game_screen.dart';
import 'package:worthbang/screens/history_screen.dart';
import 'package:worthbang/screens/home_screen.dart';
import 'package:worthbang/screens/login_screen.dart';
import 'package:worthbang/screens/price_check_screen.dart';
import 'package:worthbang/screens/profile_screen.dart';
import 'package:worthbang/screens/register_screen.dart';
import 'package:worthbang/screens/search_screen.dart';
import 'package:worthbang/screens/tools_screen.dart';
import 'package:worthbang/screens/trends_screen.dart';
import 'package:worthbang/services/data/app_database.dart';
import 'package:worthbang/utils/app.dart';
import 'package:worthbang/utils/theme.dart';

/// Stub auth: authenticated → guard router tidak redirect ke /login.
class _FakeAuthController extends AuthController {
  @override
  AuthState build() => const AuthState(
    status: AuthStatus.authenticated,
    user: AppUser(id: '1', name: 'Dan', email: 'dan@example.com'),
  );
}

/// Test anti-`RenderFlex overflow` untuk design system Monex.
///
/// Skenario: render tiap layar pada lebar device sempit (320 px, setara
/// Android kelas low-end / split screen) lalu pastikan tidak ada overflow
/// horizontal maupun vertikal. Kegagalan = ada `RenderFlex overflowed by`
/// di log Flutter.
void main() {
  // 320 px logical — devicePixelRatio 1.0 supaya logical size = 320.
  const narrow = Size(320, 640);

  void setNarrowView(WidgetTester tester) {
    tester.view.physicalSize = narrow;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// [build] dipakai sebagai closure supaya tipe `Override` (tidak
  /// diekspor Riverpod 3) tidak perlu disebut eksplisit.
  Future<void> pumpNarrow(
    WidgetTester tester,
    Widget Function() build,
  ) async {
    setNarrowView(tester);
    await tester.pumpWidget(build());
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Scope standar: DB in-memory + tema Monex dark.
  Widget app(Widget child) => ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(
            AppDatabase(NativeDatabase.memory()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: child,
        ),
      );

  group('Monex widget primitives tidak overflow di layar sempit', () {
    testWidgets('MonexSurfaceCard + MonexTransactionTile', (tester) async {
      await pumpNarrow(
        tester,
        () => app(
          Scaffold(
            body: MonexSurfaceCard(
              child: MonexTransactionTile(
                title: 'Judul kartu yang cukup panjang untuk menguji batas lebar',
                subtitle: 'Subtitle yang juga panjang untuk memastikan tile aman',
                leadingIcon: Icons.memory,
                trailing: const Text('Rp 1.500.000'),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('MonexPrimaryButton + MonexSecondaryButton', (tester) async {
      await pumpNarrow(
        tester,
        () => app(
          Scaffold(
            body: Column(
              children: [
                MonexPrimaryButton(
                  onPressed: () {},
                  label: 'Tombol utama dengan label panjang sekali',
                  icon: Icons.rocket_launch_rounded,
                ),
                const SizedBox(height: 12),
                MonexSecondaryButton(
                  onPressed: () {},
                  label: 'Tombol sekunder berlabel panjang juga',
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('MonexSegmentedControl dengan 3 label panjang', (tester) async {
      await pumpNarrow(
        tester,
        () => app(
          Scaffold(
            body: MonexSegmentedControl<String>(
              value: 'a',
              onChanged: (_) {},
              items: const [
                MonexSegment(value: 'a', label: 'Gaming'),
                MonexSegment(value: 'b', label: 'Kantor Kerja'),
                MonexSegment(value: 'c', label: 'Editing Video'),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('MonexProgressBar + MonexEmptyState', (tester) async {
      await pumpNarrow(
        tester,
        () => app(
          Scaffold(
            body: Column(
              children: [
                const MonexProgressBar(value: 0.42),
                const SizedBox(height: 12),
                MonexEmptyState(
                  icon: Icons.inbox_rounded,
                  title: 'Belum ada hasil',
                  message:
                      'Belum ada hasil yang bisa ditampilkan untuk filter ini',
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('MonexAppBar dengan judul panjang + aksi', (tester) async {
      await pumpNarrow(
        tester,
        () => app(
          Scaffold(
            body: MonexAppBar(
              title: 'Judul aplikasi yang sangat panjang sekali untuk uji',
              actions: [
                MonexCircleIconButton(
                  icon: Icons.verified_outlined,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Loader animasi (orbit + wave) tidak overflow', (tester) async {
      await pumpNarrow(
        tester,
        () => app(
          Scaffold(
            body: Column(
              children: const [
                MonexOrbitLoader(size: 56),
                SizedBox(height: 12),
                MonexWaveLoader(size: 7),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });
  });

  group('Layar aplikasi tidak overflow di 320 px', () {
    testWidgets('HomeScreen', (tester) async {
      await pumpNarrow(tester, () => app(const HomeScreen()));
      expect(tester.takeException(), isNull);
    });

    testWidgets('SearchFilterScreen', (tester) async {
      await pumpNarrow(tester, () => app(const SearchFilterScreen()));
      expect(tester.takeException(), isNull);
    });

    testWidgets('HistoryListScreen', (tester) async {
      await pumpNarrow(tester, () => app(const HistoryListScreen()));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
    });

    testWidgets('ProfileContentScreen', (tester) async {
      await pumpNarrow(
        tester,
        () => ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(_FakeAuthController.new),
            databaseProvider.overrideWithValue(
              AppDatabase(NativeDatabase.memory()),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const ProfileContentScreen(),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('LoginScreen', (tester) async {
      await pumpNarrow(tester, () => app(const LoginScreen()));
      expect(tester.takeException(), isNull);
    });

    testWidgets('RegisterScreen', (tester) async {
      await pumpNarrow(tester, () => app(const RegisterScreen()));
      expect(tester.takeException(), isNull);
    });

    testWidgets('PriceCheckScreen', (tester) async {
      await pumpNarrow(tester, () => app(const PriceCheckScreen()));
      expect(tester.takeException(), isNull);
    });

    testWidgets('BundleScreen', (tester) async {
      await pumpNarrow(tester, () => app(const BundleScreen()));
      expect(tester.takeException(), isNull);
    });

    testWidgets('BuilderScreen', (tester) async {
      await pumpNarrow(tester, () => app(const BuilderScreen()));
      expect(tester.takeException(), isNull);
    });

    testWidgets('GameScreen', (tester) async {
      await pumpNarrow(tester, () => app(const GameScreen()));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
    });

    testWidgets('ToolsScreen', (tester) async {
      await pumpNarrow(tester, () => app(const ToolsScreen()));
      expect(tester.takeException(), isNull);
    });

    testWidgets('TrendsScreenContent', (tester) async {
      await pumpNarrow(tester, () => app(const TrendsScreenContent()));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
    });

    testWidgets('ChatScreen', (tester) async {
      await pumpNarrow(tester, () => app(const ChatScreen()));
      expect(tester.takeException(), isNull);
    });
  });

  group('Bottom nav + FAB shell', () {
    testWidgets('4 tab + FAB di 320 px tanpa overflow', (tester) async {
      setNarrowView(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(_FakeAuthController.new),
            databaseProvider.overrideWithValue(
              AppDatabase(NativeDatabase.memory()),
            ),
          ],
          child: const WorthBangApp(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationDestination), findsNWidgets(4));
      expect(find.byType(MonexFab), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Kontrak design token', () {
    test('warna Monex sesuai DESIGN(reset).MD', () {
      expect(MonexColors.appBg, const Color(0xFF0C0F17));
      expect(MonexColors.surface, const Color(0xFF1B202C));
      expect(MonexColors.lime, const Color(0xFFACEF34));
      expect(MonexColors.limeBright, const Color(0xFFB8FF3B));
      expect(MonexColors.danger, const Color(0xFFF43F5E));
      expect(MonexColors.textPrimary, const Color(0xFFF8FAFC));
      expect(MonexColors.textSecondary, const Color(0xFF94A3B8));
      expect(MonexColors.textDark, const Color(0xFF020617));
    });

    test('label tab Bahasa Indonesia tetap dipakai', () {
      expect(AppStrings.tabHome, isNotEmpty);
      expect(AppStrings.tabSearch, isNotEmpty);
      expect(AppStrings.tabScanPrice, isNotEmpty);
      expect(AppStrings.tabHistory, isNotEmpty);
      expect(AppStrings.tabProfile, isNotEmpty);
    });
  });
}
