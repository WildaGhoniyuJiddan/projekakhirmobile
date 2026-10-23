import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthbang/l10n/strings.dart';
import 'package:worthbang/providers/auth_controller.dart';

/// Alur keluar akun bersama: dialog konfirmasi lalu logout lewat
/// [AuthController] (sign out + bersihkan sesi di repository, state
/// menjadi unauthenticated sehingga guard router mengarahkan ke /login).
///
/// Dipakai tombol keluar di Profil DAN tombol logout di navbar bawah —
/// satu jalur yang sama agar perilakunya tidak pernah berbeda.
Future<void> confirmLogout(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text(AppStrings.logoutTitle),
      content: const Text(AppStrings.logoutConfirm),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(AppStrings.cancelButton),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(AppStrings.logoutButton),
        ),
      ],
    ),
  );
  if (ok == true) {
    await ref.read(authControllerProvider.notifier).logout();
  }
}

/// Tombol AKSI logout untuk navbar bawah (bukan destinasi/tab):
/// mengetuknya tidak mengganti tab aktif — hanya membuka dialog
/// konfirmasi keluar lewat [confirmLogout].
///
/// Ukuran & warna diselaraskan dengan NavigationBar tema Monex
/// (tinggi 68, ikon di atas label) agar menyatu dengan bar.
class LogoutNavButton extends ConsumerWidget {
  const LogoutNavButton({super.key});

  /// Tinggi NavigationBar pada tema Monex.
  static const double barHeight = 68;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Tooltip(
      message: AppStrings.logoutButton,
      child: SizedBox(
        width: 64,
        height: barHeight,
        child: InkWell(
          key: const ValueKey('nav-logout-button'),
          onTap: () => confirmLogout(context, ref),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.logout_rounded, size: 24, color: color),
              const SizedBox(height: 2),
              Text(
                AppStrings.logoutButton,
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
