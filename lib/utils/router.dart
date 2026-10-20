import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:worthbang/providers/auth_controller.dart';
import 'package:worthbang/core/widgets/monex_widgets.dart';
import 'package:worthbang/screens/price_check_screen.dart';
import 'package:worthbang/screens/login_screen.dart';
import 'package:worthbang/screens/register_screen.dart';
import 'package:worthbang/screens/tab_screens.dart';
import 'package:worthbang/widgets/offline_banner.dart';
import 'package:worthbang/l10n/strings.dart';

/// Kunci navigator per tab — masing-masing tab punya back stack sendiri.
final _homeNavKey = GlobalKey<NavigatorState>(debugLabel: 'homeNav');
final _searchNavKey = GlobalKey<NavigatorState>(debugLabel: 'searchNav');
final _historyNavKey = GlobalKey<NavigatorState>(debugLabel: 'historyNav');
final _profileNavKey = GlobalKey<NavigatorState>(debugLabel: 'profileNav');

/// Router aplikasi sebagai provider agar bisa bereaksi ke perubahan auth.
///
/// Guard: user yang belum login diarahkan ke /login; user yang sudah login
/// tidak bisa membuka /login & /register (diarahkan ke /home).
final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authControllerProvider);

  return GoRouter(
    initialLocation: '/home',
    redirect: (context, state) {
      final loggedIn = auth.status == AuthStatus.authenticated;
      final loc = state.matchedLocation;
      final onAuthPage = loc == '/login' || loc == '/register';
      // Sesi masih dicek → jangan redirect dulu (hindari flicker).
      if (auth.status == AuthStatus.unknown) return null;
      if (!loggedIn && !onAuthPage) return '/login';
      if (loggedIn && onAuthPage) return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            BottomNavShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _homeNavKey,
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _searchNavKey,
            routes: [
              GoRoute(
                path: '/search',
                builder: (context, state) => const SearchScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _historyNavKey,
            routes: [
              GoRoute(
                path: '/history',
                builder: (context, state) => const HistoryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _profileNavKey,
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// Shell bottom navigation: 4 tab sesuai PRD (Beranda, Cari, Riwayat, Profil).
/// Banner offline (T15) tampil di atas konten semua tab.
class BottomNavShell extends ConsumerWidget {
  const BottomNavShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _goBranch(int index) {
    navigationShell.goBranch(
      index,
      // Kembali ke root tab bila tab aktif di-tap ulang.
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(child: navigationShell),
        ],
      ),
      // FAB aksi utama (DESIGN(reset) §5.6): cek harga cepat.
      floatingActionButton: MonexFab(
        tooltip: AppStrings.priceCheckTitle,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const PriceCheckScreen()),
        ),
      ),
      bottomNavigationBar: MonexBottomNavBar(
        selectedIndex: navigationShell.currentIndex,
        onSelected: _goBranch,
        items: const [
          MonexNavItem(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home,
            label: AppStrings.tabHome,
          ),
          MonexNavItem(
            icon: Icons.search_outlined,
            selectedIcon: Icons.search,
            label: AppStrings.tabSearch,
          ),
          MonexNavItem(
            icon: Icons.history_outlined,
            selectedIcon: Icons.history,
            label: AppStrings.tabHistory,
          ),
          MonexNavItem(
            icon: Icons.person_outline,
            selectedIcon: Icons.person,
            label: AppStrings.tabProfile,
          ),
        ],
      ),
    );
  }
}
