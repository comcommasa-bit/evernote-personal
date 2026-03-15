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

  /// デバイスが生体認証またはデバイス認証（PIN等）に対応しているか確認
  Future<bool> isBiometricAvailable() async {
    try {
      // デバイスが認証機構自体をサポートしているか
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      // 生体認証 or PIN/パターン が使えるか
      final canCheck = await _auth.canCheckBiometrics;
      return canCheck;
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

  /// 生体認証を実行。成功したら true を返す。
  ///
  /// Android では biometricOnly: false にすることで、
  /// 指紋センサーが認識できない場合に PIN/パターンへのフォールバックを許可します。
  /// これにより「指紋が動かない」問題を回避できます。
  Future<bool> authenticateWithBiometrics() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Evernote-personal を開くには認証してください',
        options: const AuthenticationOptions(
          biometricOnly: false,     // PIN/パターンへのフォールバックを許可
          stickyAuth: true,         // 画面を離れても認証ダイアログを保持
          sensitiveTransaction: false,
        ),
      );
    } on PlatformException catch (e) {
      // キャンセル・ロックアウト・未登録などはすべて false を返す
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

  /// 利用可能な生体認証の種類を取得（fingerprint / face / iris など）
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }
}
