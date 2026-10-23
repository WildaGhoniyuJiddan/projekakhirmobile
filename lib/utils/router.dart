import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:worthbang/providers/auth_controller.dart';
import 'package:worthbang/core/widgets/monex_widgets.dart';
import 'package:worthbang/services/core/notification_permissions.dart';
import 'package:worthbang/screens/login_screen.dart';
import 'package:worthbang/screens/register_screen.dart';
import 'package:worthbang/screens/tab_screens.dart';
import 'package:worthbang/widgets/logout_action.dart';
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
///
/// Shell ini hanya ter-render untuk user terautentikasi (guard router),
/// jadi initState-nya adalah titik paling hulu pasca-login — tempat
/// prompt izin notifikasi sekali-tanya dipasang (frame pertama).
class BottomNavShell extends ConsumerStatefulWidget {
  const BottomNavShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<BottomNavShell> createState() => _BottomNavShellState();
}

class _BottomNavShellState extends ConsumerState<BottomNavShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_promptNotificationPermission());
    });
  }

  /// Minta izin notifikasi sekali pasca-login. Semua kegagalan hanya
  /// dicatat — penolakan/kegagalan izin tidak boleh mengganggu shell.
  Future<void> _promptNotificationPermission() async {
    if (!mounted) return;
    try {
      final service =
          await ref.read(notificationPermissionServiceProvider.future);
      if (!mounted) return;
      await service.ensurePromptedOnce();
    } catch (e) {
      debugPrint('[NotifPermission] prompt awal gagal: $e');
    }
  }

  void _goBranch(int index) {
    widget.navigationShell.goBranch(
      index,
      // Kembali ke root tab bila tab aktif di-tap ulang.
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final navigationShell = widget.navigationShell;
    return Scaffold(
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(child: navigationShell),
        ],
      ),
      // TIDAK ada FAB di shell: FAB global menutupi konten semua menu
      // yang di-push di atasnya. FAB chatbot tinggal di HomeScreen —
      // hanya tampil di Beranda root (keputusan Dan 2026-10-21).
      //
      // Bar bawah: 4 destinasi tab + tombol AKSI logout di pojok paling
      // KANAN (bukan destinasi — tidak mengganti tab; mengetuknya hanya
      // membuka dialog konfirmasi keluar, jalur yang sama dengan Profil).
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: MonexBottomNavBar(
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
            ),
            const LogoutNavButton(),
          ],
        ),
      ),
    );
  }
}
