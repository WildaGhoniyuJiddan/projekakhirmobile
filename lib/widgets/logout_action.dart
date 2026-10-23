import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthbang/core/theme/monex_theme.dart' show kMonexFontFamily;
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
/// Ukuran & posisi diselaraskan dengan NavigationDestination tema Monex
/// (tinggi 68, indicator height 32, icon size 22, label font 11) agar
/// sejajar sempurna secara vertikal dan proporsional dengan menu lain.
class LogoutNavButton extends ConsumerWidget {
  const LogoutNavButton({super.key});

  /// Tinggi NavigationBar pada tema Monex.
  static const double barHeight = 68;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final navTheme = NavigationBarTheme.of(context);
    final labelStyle = navTheme.labelTextStyle?.resolve({}) ??
        TextStyle(
          fontFamily: kMonexFontFamily,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: theme.colorScheme.onSurfaceVariant,
        );
    final iconColor = navTheme.iconTheme?.resolve({})?.color ??
        theme.colorScheme.onSurfaceVariant;
    final iconSize = navTheme.iconTheme?.resolve({})?.size ?? 22.0;

    return Tooltip(
      message: AppStrings.logoutButton,
      child: Material(
        color: Colors.transparent,
        child: InkResponse(
          key: const ValueKey('nav-logout-button'),
          onTap: () => confirmLogout(context, ref),
          containedInkWell: true,
          highlightShape: BoxShape.rectangle,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 32,
                  child: Center(
                    child: Icon(
                      Icons.logout_rounded,
                      size: iconSize,
                      color: iconColor,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppStrings.logoutButton,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
