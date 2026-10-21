import 'package:local_auth/local_auth.dart';

/// Wrapper biometric (local_auth) untuk unlock sesi.
///
/// Dipakai di layar login: bila user pernah login & mengaktifkan biometric,
/// sesi dipulihkan tanpa mengetik password (FR-4).
class BiometricService {
  BiometricService([LocalAuthentication? auth])
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  /// true bila perangkat mendukung & punya biometric terdaftar.
  Future<bool> get isAvailable async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final available = await _auth.isDeviceSupported();
      final enrolled = await _auth.getAvailableBiometrics();
      return canCheck && available && enrolled.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Minta autentikasi biometric. Return true bila lolos.
  Future<bool> authenticate({String reason = 'Buka kunci WorthBang'}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}
