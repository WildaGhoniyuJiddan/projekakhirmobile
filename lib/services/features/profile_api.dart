import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:worthbang/models/auth_models.dart';
import 'package:worthbang/providers/auth_controller.dart';

final profileApiProvider = Provider<ProfileApi>(
  (ref) => ProfileApi(ref),
);

/// Profil & feedback — sekarang 100% lokal.
/// Nama & foto tersimpan di SharedPreferences; feedback tersimpan
/// sebagai riwayat lokal di perangkat (tanpa backend).
class ProfileApi {
  ProfileApi(this._ref);

  final Ref _ref;

  static const _nameKey = 'profile_name';
  static const _photoKey = 'profile_photo_path';
  static const _feedbackKey = 'feedback_history';

  /// Baca path foto lokal tersimpan (untuk restore avatar).
  static Future<String?> localPhotoPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_photoKey);
  }

  /// Baca nama lokal tersimpan.
  static Future<String?> localName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_nameKey);
  }

  /// Update profil lokal: nama dan/atau foto. Kembalikan user terbarui.
  Future<AppUser> updateProfile({String? name, String? photoPath}) async {
    final current = _ref.read(authControllerProvider).user;
    if (current == null) {
      throw StateError('Belum login');
    }
    final prefs = await SharedPreferences.getInstance();
    final newName = name ?? await localName() ?? current.name;
    final newPhoto = photoPath ?? prefs.getString(_photoKey);
    if (name != null) await prefs.setString(_nameKey, name);
    if (photoPath != null) await prefs.setString(_photoKey, photoPath);
    return AppUser(
      id: current.id,
      name: newName,
      email: current.email,
      photoUrl: newPhoto,
    );
  }

  /// Simpan feedback ke riwayat lokal perangkat.
  Future<void> sendFeedback({
    required int rating,
    required String kesan,
    required String saran,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_feedbackKey);
    final list = raw == null
        ? <Map<String, dynamic>>[]
        : (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    list.add({
      'rating': rating,
      'kesan': kesan,
      'saran': saran,
      'at': DateTime.now().toIso8601String(),
    });
    await prefs.setString(_feedbackKey, jsonEncode(list));
  }

  /// Riwayat feedback lokal (untuk ditampilkan bila perlu).
  Future<List<Map<String, dynamic>>> feedbackHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_feedbackKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }
}

/// Pengaturan aplikasi: tilt 3D & tema (SharedPreferences).
/// AsyncNotifier agar hydrate dari disk selesai sebelum state dipakai.
class AppSettings {
  const AppSettings({
    this.tiltEnabled = true,
    this.themeMode = ThemeMode.system,
  });

  final bool tiltEnabled;
  final ThemeMode themeMode;

  AppSettings copyWith({bool? tiltEnabled, ThemeMode? themeMode}) =>
      AppSettings(
        tiltEnabled: tiltEnabled ?? this.tiltEnabled,
        themeMode: themeMode ?? this.themeMode,
      );
}

class SettingsController extends AsyncNotifier<AppSettings> {
  static const _tiltKey = 'settings_tilt_enabled';
  static const _themeKey = 'settings_theme_mode';

  @override
  Future<AppSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      tiltEnabled: prefs.getBool(_tiltKey) ?? true,
      themeMode: ThemeMode
          .values[(prefs.getInt(_themeKey) ?? 0).clamp(0, 2)],
    );
  }

  Future<void> setTiltEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_tiltKey, v);
    final cur = state.value ?? const AppSettings();
    state = AsyncData(cur.copyWith(tiltEnabled: v));
  }

  Future<void> setThemeMode(ThemeMode m) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, m.index);
    final cur = state.value ?? const AppSettings();
    state = AsyncData(cur.copyWith(themeMode: m));
  }
}

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>(
        SettingsController.new);

/// Helper baca sinkron dengan fallback default.
extension SettingsX on AsyncValue<AppSettings> {
  AppSettings get orDefault => value ?? const AppSettings();
}
