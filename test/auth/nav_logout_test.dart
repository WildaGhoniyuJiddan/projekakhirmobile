import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worthbang/l10n/strings.dart';
import 'package:worthbang/models/auth_models.dart';
import 'package:worthbang/providers/auth_controller.dart';
import 'package:worthbang/services/core/notification_permissions.dart';
import 'package:worthbang/utils/router.dart' show BottomNavShell;
import 'package:worthbang/utils/theme.dart';
import 'package:worthbang/widgets/logout_action.dart';

/// Auth fake: langsung terautentikasi; logout dicatat & membalik status.
class _FakeAuthController extends AuthController {
  int logoutCalls = 0;

  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        user: AppUser(id: '1', name: 'Dan', email: 'dan@example.com'),
      );

  @override
  Future<void> logout() async {
    logoutCalls++;
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

/// Gateway notifikasi fake: izin selalu aktif (tidak memicu request).
class _FakeGateway implements NotificationPermissionGateway {
  @override
  Future<bool?> areNotificationsEnabled() async => true;

  @override
  Future<bool?> requestPermission() async => true;

  @override
  Future<void> openNotificationSettings() async {}
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAuthController fakeAuth;

  Future<void> pumpShell(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    fakeAuth = _FakeAuthController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() => fakeAuth),
          notificationPermissionServiceProvider.overrideWith(
            (ref) async => NotificationPermissionService(
              gateway: _FakeGateway(),
              prefs: prefs,
            ),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: _shellRouter(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('tombol logout tampil di pojok paling kanan navbar bawah',
      (tester) async {
    await pumpShell(tester);

    expect(find.byType(LogoutNavButton), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(LogoutNavButton),
        matching: find.text(AppStrings.logoutButton),
      ),
      findsOneWidget,
    );
    // Paling kanan: pusat tombol logout di kanan pusat destinasi Profil.
    final logoutCenter =
        tester.getCenter(find.byKey(const ValueKey('nav-logout-button')));
    final profileCenter =
        tester.getCenter(find.byType(NavigationDestination).at(3));
    expect(logoutCenter.dx, greaterThan(profileCenter.dx));
    // Destinasi tab tetap tepat 4 — logout adalah aksi, bukan tab.
    expect(find.byType(NavigationDestination), findsNWidgets(4));
  });

  testWidgets('ketuk logout → dialog; Batal → tetap di shell, tak logout',
      (tester) async {
    await pumpShell(tester);

    await tester.tap(find.byKey(const ValueKey('nav-logout-button')));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.logoutConfirm), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, AppStrings.cancelButton));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.logoutConfirm), findsNothing);
    expect(fakeAuth.logoutCalls, 0);
    expect(find.text('page'), findsWidgets); // masih di shell
  });

  testWidgets('ketuk logout → Keluar → urutan logout terpanggil', (
    tester,
  ) async {
    await pumpShell(tester);

    await tester.tap(find.byKey(const ValueKey('nav-logout-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, AppStrings.logoutButton),
    );
    await tester.pumpAndSettle();

    expect(fakeAuth.logoutCalls, 1);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(BottomNavShell)),
    );
    expect(
      container.read(authControllerProvider).status,
      AuthStatus.unauthenticated,
    );
  });
}
