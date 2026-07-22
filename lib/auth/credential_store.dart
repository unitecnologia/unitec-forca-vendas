import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Guarda a senha do app de forma segura (só quando a digital está ativa).
class CredentialStore {
  CredentialStore._();

  static const _senhaKey = 'fv_app_senha';
  static const _storage = FlutterSecureStorage();
  static final _auth = LocalAuthentication();

  static Future<bool> canUseBiometrics() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      final canCheck = await _auth.canCheckBiometrics;
      if (!canCheck) return false;
      final available = await _auth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticate({String reason = 'Confirme sua identidade'}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
      );
    } catch (_) {
      return false;
    }
  }

  static Future<void> saveSenha(String senha) async {
    await _storage.write(key: _senhaKey, value: senha);
  }

  static Future<String?> readSenha() async {
    return _storage.read(key: _senhaKey);
  }

  static Future<void> clearSenha() async {
    await _storage.delete(key: _senhaKey);
  }
}
