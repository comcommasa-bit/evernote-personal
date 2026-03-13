import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const LockScreen({super.key, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _auth    = LocalAuthentication();
  final _storage = const FlutterSecureStorage();
  final _pwCtrl  = TextEditingController();

  bool _fpActive  = false;
  bool _obscure   = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
  }

  Future<void> _tryBiometric() async {
    try {
      final canCheck  = await _auth.canCheckBiometrics;
      final available = await _auth.isDeviceSupported();
      if (!canCheck || !available) return;

      setState(() => _fpActive = true);
      final ok = await _auth.authenticate(
        localizedReason: 'Evernote-personalを開く',
        options: const AuthenticationOptions(biometricOnly: true),
      );
      setState(() => _fpActive = false);
      if (ok) widget.onUnlocked();
    } catch (_) {
      setState(() => _fpActive = false);
    }
  }

  Future<void> _checkPassword() async {
    final saved = await _storage.read(key: 'app_password');
    if (saved == null) {
      // 初回：パスワードを設定
      await _storage.write(key: 'app_password', value: _pwCtrl.text);
      widget.onUnlocked();
    } else if (saved == _pwCtrl.text) {
      widget.onUnlocked();
    } else {
      setState(() => _error = 'パスワードが違います');
    }
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0EEEA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── アプリアイコン ──
                Container(
                  width: 180, height: 180,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7B4DBF),
                    borderRadius: BorderRadius.circular(40),
                    boxShadow: [BoxShadow(
                      color: const Color(0xFF6C3CBF).withOpacity(0.25),
                      blurRadius: 32, offset: const Offset(0, 10),
                    )],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(40),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Image.asset(
                        'assets/images/hippo.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.pets,
                          size: 80,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // ── タイトル ──
                const Text('Evernote-personal',
                  style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w800,
                    color: Color(0xFF3A1F6E), letterSpacing: -0.4,
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
                        hintText: 'Enter Password',
                        hintStyle: const TextStyle(color: Color(0xFFAAAAAA)),
                        filled: true, fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFFE0DDE8)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFFE0DDE8)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                            color: const Color(0xFFAAAAAA), size: 20),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                        errorText: _error,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // 指紋ボタン
                  GestureDetector(
                    onTap: _tryBiometric,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(
                          color: _fpActive
                              ? const Color(0xFF4A90E8).withOpacity(0.4)
                              : Colors.black.withOpacity(0.10),
                          blurRadius: _fpActive ? 12 : 6,
                          spreadRadius: _fpActive ? 2 : 0,
                        )],
                      ),
                      child: Icon(Icons.fingerprint,
                        size: 30,
                        color: _fpActive
                            ? const Color(0xFF4A90E8)
                            : const Color(0xFF5A7ABF),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),

                // ── ボタン ──
                Row(children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => _pwCtrl.clear(),
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFFE0DDE8),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Cancel',
                        style: TextStyle(color: Color(0xFF777777), fontSize: 16, fontWeight: FontWeight.w600)),
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
                        shadowColor: const Color(0xFF4A80E8).withOpacity(0.4),
                      ),
                      child: const Text('Continue',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
