import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:flutter/services.dart';

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
  /// デバイスが生体認証に対応しているか確認
  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      if (!canCheck || !supported) return false;
      // 登録済みの生体情報があるか確認
      final biometrics = await _auth.getAvailableBiometrics();
      return biometrics.isNotEmpty;
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
  /// [allowDeviceCredentials] : true にすると PIN/パターン/パスワードでのフォールバックを許可
  Future<bool> authenticateWithBiometrics(
      {bool allowDeviceCredentials = false}) async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Evernote-personalを開くには認証してください',
        options: AuthenticationOptions(
          biometricOnly: !allowDeviceCredentials,
          stickyAuth: true,    // 画面を離れても認証状態を保持
          sensitiveTransaction: false,
        ),
      );
    } on PlatformException catch (e) {
      // ユーザーがキャンセル・認証不可などの場合は false を返す
      if (e.code == auth_error.notAvailable ||
          e.code == auth_error.notEnrolled ||
          e.code == auth_error.lockedOut ||
          e.code == auth_error.permanentlyLockedOut ||
          e.code == auth_error.passcodeNotSet) {
        return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 利用可能な生体認証の種類を取得
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }
}
