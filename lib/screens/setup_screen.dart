import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';

/// 初回起動時のセットアップ画面
/// パスワード設定 → 生体認証登録案内 の2ステップ
class SetupScreen extends StatefulWidget {
  final VoidCallback onSetupComplete;
  const SetupScreen({super.key, required this.onSetupComplete});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _auth = AuthService();
  final _pwCtrl = TextEditingController();
  final _pwConfirmCtrl = TextEditingController();

  int _step = 0; // 0=PW入力, 1=生体認証案内
  bool _obscure1 = true;
  bool _obscure2 = true;
  String? _error;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  @override
  void dispose() {
    _pwCtrl.dispose();
    _pwConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkBiometric() async {
    final ok = await _auth.isBiometricAvailable();
    if (mounted) setState(() => _biometricAvailable = ok);
  }

  Future<void> _submitPassword() async {
    final pw = _pwCtrl.text.trim();
    final confirm = _pwConfirmCtrl.text.trim();
    if (pw.isEmpty) {
      setState(() => _error = 'パスワードを入力してください');
      return;
    }
    if (pw.length < 4) {
      setState(() => _error = '4文字以上で入力してください');
      return;
    }
    if (pw != confirm) {
      setState(() => _error = 'パスワードが一致しません');
      return;
    }
    await _auth.setPassword(pw);
    if (_biometricAvailable) {
      setState(() {
        _step = 1;
        _error = null;
      });
    } else {
      await _auth.setBiometricEnabled(false);
      widget.onSetupComplete();
    }
  }

  Future<void> _enableBiometric() async {
    final ok = await _auth.authenticateWithBiometrics();
    if (ok) {
      await _auth.setBiometricEnabled(true);
      widget.onSetupComplete();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('生体認証に失敗しました。後で設定から有効にできます。')),
        );
      }
    }
  }

  Future<void> _skipBiometric() async {
    await _auth.setBiometricEnabled(false);
    widget.onSetupComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0EEEA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 40).copyWith(top: 48, bottom: 32),
            child: _step == 0 ? _buildPasswordStep() : _buildBiometricStep(),
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // アイコン
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6C3CBF).withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 8),
              )
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Image.asset('assets/images/hippo.png', fit: BoxFit.contain),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Evernote-personal',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF3A1F6E),
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'はじめにパスワードを設定してください',
          style: TextStyle(fontSize: 13, color: Color(0xFF888888)),
        ),
        const SizedBox(height: 32),
        // パスワード入力
        TextField(
          controller: _pwCtrl,
          obscureText: _obscure1,
          onSubmitted: (_) => _submitPassword(),
          decoration: InputDecoration(
            hintText: 'パスワード（4文字以上）',
            hintStyle: const TextStyle(color: Color(0xFFAAAAAA)),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE0DDE8)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE0DDE8)),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            suffixIcon: IconButton(
              icon: Icon(
                _obscure1
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: const Color(0xFFAAAAAA),
                size: 20,
              ),
              onPressed: () => setState(() => _obscure1 = !_obscure1),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 確認用パスワード
        TextField(
          controller: _pwConfirmCtrl,
          obscureText: _obscure2,
          onSubmitted: (_) => _submitPassword(),
          decoration: InputDecoration(
            hintText: 'パスワード（確認）',
            hintStyle: const TextStyle(color: Color(0xFFAAAAAA)),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE0DDE8)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE0DDE8)),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            suffixIcon: IconButton(
              icon: Icon(
                _obscure2
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: const Color(0xFFAAAAAA),
                size: 20,
              ),
              onPressed: () => setState(() => _obscure2 = !_obscure2),
            ),
            errorText: _error,
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _submitPassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A80E8),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              elevation: 4,
              shadowColor: const Color(0xFF4A80E8).withValues(alpha: 0.4),
            ),
            child: const Text('次へ',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Widget _buildBiometricStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4A90E8).withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, 6),
              )
            ],
          ),
          child: const Icon(Icons.fingerprint,
              size: 56, color: Color(0xFF4A90E8)),
        ),
        const SizedBox(height: 24),
        const Text(
          '生体認証を設定しますか？',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF3A1F6E),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '指紋認証・顔認証でかんたんにロックを解除できます。\nあとで設定から変更することもできます。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Color(0xFF888888), height: 1.6),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _enableBiometric,
            icon: const Icon(Icons.fingerprint, size: 20),
            label: const Text('生体認証を有効にする',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A80E8),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              elevation: 4,
              shadowColor: const Color(0xFF4A80E8).withValues(alpha: 0.4),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: _skipBiometric,
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFFE0DDE8),
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            child: Text('スキップ',
                style: GoogleFonts.notoSansJp(
                    color: const Color(0xFF777777),
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}
