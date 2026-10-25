import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider service izin notifikasi (async karena butuh SharedPreferences).
/// Di-override dengan service berbasis gateway fake di test.
final notificationPermissionServiceProvider =
    FutureProvider<NotificationPermissionService>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return NotificationPermissionService(
    gateway: PluginNotificationPermissionGateway(),
    prefs: prefs,
  );
});

/// Gateway mentah ke plugin notifikasi + Pengaturan OS.
/// Sengaja tipis agar mudah di-mock: semua keputusan ada di
/// [NotificationPermissionService], gateway hanya meneruskan panggilan.
abstract class NotificationPermissionGateway {
  /// Status izin aktual; `null` bila platform tidak didukung.
  Future<bool?> areNotificationsEnabled();

  /// Memunculkan dialog izin sistem. Hasil akhir izin (bila diketahui).
  Future<bool?> requestPermission();

  /// Membuka halaman Pengaturan Notifikasi OS untuk aplikasi ini.
  Future<void> openNotificationSettings();

  /// Akses alarm tepat waktu (Android 12+): true bila aplikasi boleh
  /// menjadwalkan alarm exact. Platform lain selalu true.
  Future<bool> canScheduleExactAlarms();

  /// Membuka layar Pengaturan "Alarm dan pengingat" OS untuk aplikasi
  /// ini (satu-satunya cara mengaktifkan akses alarm exact: Android
  /// tidak menyediakan popup izin untuk akses ini).
  Future<void> openExactAlarmSettings();
}

class PluginNotificationPermissionGateway
    implements NotificationPermissionGateway {
  PluginNotificationPermissionGateway(
      [FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  IOSFlutterLocalNotificationsPlugin? get _ios => _plugin
      .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

  @override
  Future<bool?> areNotificationsEnabled() async {
    final android = _android;
    if (android != null) return android.areNotificationsEnabled();
    final ios = _ios;
    if (ios != null) {
      final options = await ios.checkPermissions();
      return options?.isEnabled;
    }
    return null; // Platform selain Android/iOS: tidak berlaku.
  }

  @override
  Future<bool?> requestPermission() async {
    final android = _android;
    if (android != null) return android.requestNotificationsPermission();
    final ios = _ios;
    if (ios != null) {
      return ios.requestPermissions(alert: true, badge: true, sound: true);
    }
    return null;
  }

  @override
  Future<void> openNotificationSettings() =>
      AppSettings.openAppSettings(type: AppSettingsType.notification);

  /// Channel native ke MainActivity: AlarmManager.canScheduleExactAlarms
  /// + intent Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM.
  static const _exactAlarmChannel =
      MethodChannel('worthbang/exact_alarm');

  @override
  Future<bool> canScheduleExactAlarms() async {
    try {
      final allowed = await _exactAlarmChannel.invokeMethod<bool>(
        'canScheduleExactAlarms',
      );
      return allowed ?? true;
    } catch (e) {
      debugPrint('[NotifPermission] cek exact alarm gagal: $e');
      return true; // Optimistis: bila jadwal gagal, pemanggil menampilkan dialog.
    }
  }

  @override
  Future<void> openExactAlarmSettings() async {
    await _exactAlarmChannel.invokeMethod<void>('openExactAlarmSettings');
  }
}

/// Logika izin notifikasi: prompt SEKALI pasca-login + cek status
/// real-time untuk pre-flight fitur (mis. tombol Simulasi Notifikasi).
///
/// Prinsip: kegagalan apa pun di jalur ini tidak boleh mengganggu
/// navigasi/fitur lain — error dicatat via debugPrint, tidak ditelan.
class NotificationPermissionService {
  NotificationPermissionService({
    required this._gateway,
    required this._prefs,
  });

  final NotificationPermissionGateway _gateway;
  final SharedPreferences _prefs;

  /// Penanda "sudah pernah diminta izin" — versi v1 agar skema bisa
  /// di-reset di masa depan dengan menaikkan sufiks.
  static const promptedKey = 'notif_permission_prompted_v1';

  bool _isChecking = false;

  /// Status izin aktual untuk keputusan UI. Error/status tak diketahui
  /// diperlakukan sebagai NONAKTIF (aman: fitur menampilkan panduan,
  /// bukan gagal diam-diam).
  Future<bool> isEnabled() async {
    try {
      return await _gateway.areNotificationsEnabled() ?? false;
    } catch (e) {
      debugPrint('[NotifPermission] cek status izin gagal: $e');
      return false;
    }
  }

  /// Flow prompt sekali di frame pertama pasca-login:
  /// 1. Izin sudah aktif → tandai selesai, berhenti tanpa dialog.
  /// 2. Flag lokal sudah true → jangan pernah meminta lagi.
  /// 3. Selain itu → simpan flag DULU (anti race/rebuild), baru minta.
  Future<void> ensurePromptedOnce() async {
    if (_isChecking) return;
    _isChecking = true;
    try {
      final enabled = await _gateway.areNotificationsEnabled();
      if (enabled == true) {
        await _prefs.setBool(promptedKey, true);
        return;
      }
      if (enabled == null) {
        debugPrint('[NotifPermission] platform tidak didukung, '
            'prompt izin dilewati.');
        return;
      }
      final prompted = _prefs.getBool(promptedKey) ?? false;
      if (prompted) return;
      await _prefs.setBool(promptedKey, true);
      await _gateway.requestPermission();
    } catch (e) {
      debugPrint('[NotifPermission] prompt izin gagal: $e');
    } finally {
      _isChecking = false;
    }
  }

  /// Buka Pengaturan Notifikasi OS. `false` bila gagal (pemanggil
  /// menampilkan pesan — tidak ada kegagalan diam-diam).
  Future<bool> openNotificationSettings() async {
    try {
      await _gateway.openNotificationSettings();
      return true;
    } catch (e) {
      debugPrint('[NotifPermission] buka Pengaturan gagal: $e');
      return false;
    }
  }

  /// Status akses alarm tepat waktu (Android 12+). Error dianggap
  /// diizinkan agar jadwal tetap dicoba; kegagalan jadwal ditangani
  /// pemanggil lewat dialog, bukan banner exception mentah.
  Future<bool> isExactAlarmAllowed() async {
    try {
      return await _gateway.canScheduleExactAlarms();
    } catch (e) {
      debugPrint('[NotifPermission] cek exact alarm gagal: $e');
      return true;
    }
  }

  /// Buka layar Pengaturan "Alarm dan pengingat" OS. `false` bila gagal.
  Future<bool> openExactAlarmSettings() async {
    try {
      await _gateway.openExactAlarmSettings();
      return true;
    } catch (e) {
      debugPrint('[NotifPermission] buka Pengaturan alarm gagal: $e');
      return false;
    }
  }

  /// Minta izin lewat popup sistem, untuk aksi eksplisit pengguna
  /// (mis. tombol Simulasi Notifikasi).
  ///
  /// Sengaja TIDAK memakai [ensurePromptedOnce]: ketukan tombol adalah
  /// niat eksplisit, jadi popup selalu dimunculkan tanpa membaca/menulis
  /// flag prompt-sekali pasca-login. Mengembalikan status izin SETELAH
  /// popup ditutup (cek ulang real-time, karena hasil request bisa null
  /// di sebagian platform; bila izin ditolak permanen, popup tidak
  /// muncul dan status tetap nonaktif).
  Future<bool> requestPermission() async {
    try {
      await _gateway.requestPermission();
    } catch (e) {
      debugPrint('[NotifPermission] minta izin gagal: $e');
    }
    return isEnabled();
  }
}
