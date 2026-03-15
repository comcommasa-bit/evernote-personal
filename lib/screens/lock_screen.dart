import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';

class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const LockScreen({super.key, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _auth = AuthService();
  final _pwCtrl = TextEditingController();

  bool _fpActive = false;
  bool _biometricEnabled = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initBiometric();
  }

  @override
  void dispose() {
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _initBiometric() async {
    final enabled = await _auth.isBiometricEnabled();
    if (!mounted) return;
    setState(() => _biometricEnabled = enabled);
    // 有効なら自動で生体認証を試みる
    if (enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
    }
  }

  Future<void> _tryBiometric() async {
    if (!_biometricEnabled) return;
    final available = await _auth.isBiometricAvailable();
    if (!available || !mounted) return;

    setState(() => _fpActive = true);
    final ok = await _auth.authenticateWithBiometrics();
    if (!mounted) return;
    setState(() => _fpActive = false);
    if (ok) widget.onUnlocked();
  }

  Future<void> _checkPassword() async {
    final pw = _pwCtrl.text;
    if (pw.isEmpty) {
      setState(() => _error = 'パスワードを入力してください');
      return;
    }
    final ok = await _auth.checkPassword(pw);
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
    } else {
      setState(() => _error = 'パスワードが違います');
      _pwCtrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0EEEA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 40)
                .copyWith(top: 48, bottom: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── アプリアイコン ──
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6C3CBF).withValues(alpha: 0.15),
                        blurRadius: 28,
                        offset: const Offset(0, 8),
                      )
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: Image.asset(
                      'assets/images/hippo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 22),

                // ── タイトル ──
                Text(
                  'Evernote-personal',
                  style: GoogleFonts.notoSansJp(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF3A1F6E),
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 32),

                // ── パスワード入力 ──
                TextField(
                  controller: _pwCtrl,
                  obscureText: _obscure,
                  onSubmitted: (_) => _checkPassword(),
                  style: GoogleFonts.notoSansJp(
                    fontSize: 15,
                    color: const Color(0xFF1A1A1A),
                  ),
                  decoration: InputDecoration(
                    hintText: 'パスワードを入力',
                    hintStyle: GoogleFonts.notoSansJp(
                        color: const Color(0xFFAAAAAA), fontSize: 14),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: Color(0xFFE0DDE8)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: Color(0xFFE0DDE8)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                          color: Color(0xFF4A80E8), width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: const Color(0xFFAAAAAA),
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscure = !_obscure),
                    ),
                    errorText: _error,
                    errorStyle: GoogleFonts.notoSansJp(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 16),

                // ── ログインボタン ──
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _checkPassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4A80E8),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 3,
                      shadowColor:
                          const Color(0xFF4A80E8).withValues(alpha: 0.35),
                    ),
                    child: Text(
                      'ログイン',
                      style: GoogleFonts.notoSansJp(
                          fontSize: 16, fontWeight: FontWeight.w700,
                          color: Colors.white),
                    ),
                  ),
                ),

                // ── 指紋認証ボタン（有効時のみ表示） ──
                if (_biometricEnabled) ...[
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: _tryBiometric,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _fpActive
                                ? const Color(0xFF4A90E8).withValues(alpha: 0.45)
                                : Colors.black.withValues(alpha: 0.10),
                            blurRadius: _fpActive ? 16 : 8,
                            spreadRadius: _fpActive ? 3 : 0,
                          )
                        ],
                      ),
                      child: Icon(
                        Icons.fingerprint,
                        size: 36,
                        color: _fpActive
                            ? const Color(0xFF4A90E8)
                            : const Color(0xFF5A7ABF),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _fpActive ? '認証中...' : '指紋でログイン',
                    style: GoogleFonts.notoSansJp(
                        fontSize: 12, color: const Color(0xFF888888)),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      _pwCtrl.clear();
                      setState(() => _error = null);
                    },
                    child: Text(
                      'クリア',
                      style: GoogleFonts.notoSansJp(
                          color: const Color(0xFF999999), fontSize: 13),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
