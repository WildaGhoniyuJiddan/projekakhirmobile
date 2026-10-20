import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worthbang/models/auth_models.dart';
import 'package:worthbang/providers/auth_controller.dart';
import 'package:worthbang/services/profile_api.dart';

class _AuthenticatedAuthController extends AuthController {
  @override
  AuthState build() => const AuthState(
    status: AuthStatus.authenticated,
    user: AppUser(id: '1', name: 'Dani', email: 'dan@example.com'),
  );
}

void main() {
  group('ProfileApi (profil lokal)', () {
    test('updateProfile nama', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_AuthenticatedAuthController.new),
        ],
      );
      addTearDown(container.dispose);
      final api = container.read(profileApiProvider);
      final user = await api.updateProfile(name: 'Budi');
      expect(user.name, 'Budi');
      expect(user.email, 'dan@example.com');
    });

    test('updateProfile foto → photo_url terisi', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_AuthenticatedAuthController.new),
        ],
      );
      addTearDown(container.dispose);
      final api = container.read(profileApiProvider);
      final user = await api.updateProfile(photoPath: '/tmp/foto.jpg');
      expect(user.photoUrl, '/tmp/foto.jpg');
    });

    test('sendFeedback sukses', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final api = container.read(profileApiProvider);
      await api.sendFeedback(rating: 5, kesan: 'Bagus', saran: '-');
      expect((await api.feedbackHistory()).single['rating'], 5);
    });
  });

  group('SettingsController', () {
    test('default + ubah tilt & tema tersimpan', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Tunggu hydrate dari disk selesai.
      await container.read(settingsControllerProvider.future);
      final ctrl = container.read(settingsControllerProvider.notifier);
      expect(
        container.read(settingsControllerProvider).orDefault.tiltEnabled,
        isTrue,
      );
      expect(
        container.read(settingsControllerProvider).orDefault.themeMode,
        ThemeMode.system,
      );

      await ctrl.setTiltEnabled(false);
      expect(
        container.read(settingsControllerProvider).orDefault.tiltEnabled,
        isFalse,
      );

      await ctrl.setThemeMode(ThemeMode.dark);
      expect(
        container.read(settingsControllerProvider).orDefault.themeMode,
        ThemeMode.dark,
      );

      // Persistensi: baca ulang dari prefs.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('settings_tilt_enabled'), isFalse);
      expect(prefs.getInt('settings_theme_mode'), ThemeMode.dark.index);
    });
  });
}
