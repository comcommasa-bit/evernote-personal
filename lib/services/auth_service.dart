import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// パスワード・生体認証をまとめたサービス
class AuthService {
  static final AuthService _i = AuthService._();
  factory AuthService() => _i;
  AuthService._();

  final _storage = const FlutterSecureStorage();
  final _auth = LocalAuthentication();

  static const _keyPassword = 'app_password';
  static const _keyBiometricEnabled = 'biometric_enabled';

  // ── パスワード ──────────────────────────
  Future<bool> hasPassword() async {
    final v = await _storage.read(key: _keyPassword);
    return v != null && v.isNotEmpty;
  }

  Future<void> setPassword(String pw) async {
    await _storage.write(key: _keyPassword, value: pw);
  }

  Future<bool> checkPassword(String pw) async {
    final saved = await _storage.read(key: _keyPassword);
    return saved == pw;
  }

  // ── 生体認証 ────────────────────────────
  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      return canCheck && supported;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isBiometricEnabled() async {
    final v = await _storage.read(key: _keyBiometricEnabled);
    return v == 'true';
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await _storage.write(
        key: _keyBiometricEnabled, value: enabled ? 'true' : 'false');
  }

  /// 生体認証を実行。成功したら true を返す
  Future<bool> authenticateWithBiometrics() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Evernote-personalを開く',
        options: const AuthenticationOptions(biometricOnly: true),
      );
    } catch (_) {
      return false;
    }
  }
}
