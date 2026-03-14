import 'package:flutter/material.dart';
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
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
  }

  @override
  void dispose() {
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _tryBiometric() async {
    final enabled = await _auth.isBiometricEnabled();
    if (!enabled) return;
    final available = await _auth.isBiometricAvailable();
    if (!available) return;

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
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(34),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6C3CBF).withValues(alpha: 0.18),
                        blurRadius: 28,
                        offset: const Offset(0, 8),
                      )
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(34),
                    child: Image.asset(
                      'assets/images/hippo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // ── タイトル ──
                const Text(
                  'Evernote-personal',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF3A1F6E),
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 36),

                // ── パスワード + 指紋 ──
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _pwCtrl,
                      obscureText: _obscure,
                      onSubmitted: (_) => _checkPassword(),
                      decoration: InputDecoration(
                        hintText: 'パスワードを入力',
                        hintStyle:
                            const TextStyle(color: Color(0xFFAAAAAA)),
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
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // 指紋ボタン（有効時のみ目立つ）
                  FutureBuilder<bool>(
                    future: _auth.isBiometricEnabled(),
                    builder: (_, snap) {
                      final enabled = snap.data ?? false;
                      return GestureDetector(
                        onTap: _tryBiometric,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: _fpActive
                                    ? const Color(0xFF4A90E8)
                                        .withValues(alpha: 0.4)
                                    : Colors.black.withValues(alpha: 0.10),
                                blurRadius: _fpActive ? 12 : 6,
                                spreadRadius: _fpActive ? 2 : 0,
                              )
                            ],
                          ),
                          child: Icon(
                            Icons.fingerprint,
                            size: 30,
                            color: _fpActive
                                ? const Color(0xFF4A90E8)
                                : enabled
                                    ? const Color(0xFF5A7ABF)
                                    : const Color(0xFFCCCCCC),
                          ),
                        ),
                      );
                    },
                  ),
                ]),
                const SizedBox(height: 20),

                // ── ボタン ──
                Row(children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        _pwCtrl.clear();
                        setState(() => _error = null);
                      },
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFFE0DDE8),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text(
                        'キャンセル',
                        style: TextStyle(
                            color: Color(0xFF777777),
                            fontSize: 16,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _checkPassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4A80E8),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 4,
                        shadowColor:
                            const Color(0xFF4A80E8).withValues(alpha: 0.4),
                      ),
                      child: const Text(
                        'ログイン',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
