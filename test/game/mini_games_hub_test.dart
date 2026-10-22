import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worthbang/utils/app.dart';
import 'package:worthbang/providers/providers.dart';
import 'package:worthbang/services/data/app_database.dart';
import 'package:worthbang/models/auth_models.dart';
import 'package:worthbang/providers/auth_controller.dart';
import 'package:worthbang/l10n/strings.dart';
import 'package:worthbang/screens/mini_games_screen.dart';
import 'package:worthbang/screens/game_screen.dart';
import 'package:worthbang/screens/zero_g_thermal_screen.dart';

/// Stub auth: langsung authenticated agar guard router tidak redirect ke /login.
class _FakeAuthController extends AuthController {
  @override
  AuthState build() => const AuthState(
    status: AuthStatus.authenticated,
    user: AppUser(id: '1', name: 'Dan', email: 'dan@example.com'),
  );
}

/// Widget test hub Mini Games:
/// - Beranda hanya punya SATU entri game: "Mini Games" (tidak ada lagi
///   entri langsung Tebak Harga / Protokol Zero-G).
/// - Hub memuat dua pilihan; tap "Tebak Harga" membuka GameScreen dan
///   tap "Zero-G Thermal" membuka ZeroGThermalScreen.
void main() {
  final memDb = AppDatabase(NativeDatabase.memory());

  ProviderScope app() => ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(_FakeAuthController.new),
      databaseProvider.overrideWithValue(memDb),
    ],
    child: const WorthBangApp(),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'Beranda: satu entri Mini Games membuka hub dua game',
    (WidgetTester tester) async {
      // Permukaan tinggi agar seluruh grid menu Beranda terbangun.
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      // Tepat satu entri game di menu awal, tanpa entri game langsung.
      expect(find.text(AppStrings.miniGamesTitle), findsOneWidget);
      expect(find.text('Protokol Zero-G'), findsNothing);
      expect(find.text(AppStrings.gameTitle), findsNothing);
      expect(find.text(AppStrings.zeroGTitle), findsNothing);

      // Buka hub Mini Games.
      await tester.tap(find.text(AppStrings.miniGamesTitle));
      await tester.pumpAndSettle();
      expect(find.byType(MiniGamesScreen), findsOneWidget);

      // Hub memuat dua pilihan game.
      expect(find.text(AppStrings.gameTitle), findsOneWidget);
      expect(find.text(AppStrings.zeroGTitle), findsOneWidget);

      // Pilihan 1: Tebak Harga membuka GameScreen.
      // Catatan: GameScreen menampilkan MonexOrbitLoader (animasi berputar)
      // selama soal dimuat, jadi pumpAndSettle tidak dipakai di sini —
      // cukup pump terbatas, navigasinya yang diverifikasi.
      await tester.tap(find.text(AppStrings.gameTitle));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(GameScreen), findsOneWidget);

      // Kembali ke hub.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(MiniGamesScreen), findsOneWidget);

      // Pilihan 2: Zero-G Thermal membuka ZeroGThermalScreen.
      await tester.tap(find.text(AppStrings.zeroGTitle));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ZeroGThermalScreen), findsOneWidget);
    },
  );
}
