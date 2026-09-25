import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

enum AppThemeMode { white, dark, purple, blue, orange, glass }

class AppColors {
  final Color bg, sidebar, card, header, text, subtext;
  final Color accent, accentSoft, accentText;
  final Color border, active, activeText, input, icon;
  final Color shadow;
  final double shadowBlur;
  final double blur;

  const AppColors({
    required this.bg, required this.sidebar, required this.card,
    required this.header, required this.text, required this.subtext,
    required this.accent, required this.accentSoft, required this.accentText,
    required this.border, required this.active, required this.activeText,
    required this.input, required this.icon,
    this.shadow = const Color(0x0A000000), this.shadowBlur = 4,
    this.blur = 0,
  });
}

class AppThemeData {
  static const themes = {
    AppThemeMode.white: AppColors(
      bg: Color(0xFFF4F4F4), sidebar: Color(0xFFFFFFFF),
      card: Color(0xFFFFFFFF), header: Color(0xFFFFFFFF),
      text: Color(0xFF1A1A1A), subtext: Color(0xFF888888),
      accent: Color(0xFF3D9970), accentSoft: Color(0xFFEAF5F0),
      accentText: Color(0xFFFFFFFF), border: Color(0xFFE8E8E8),
      active: Color(0xFFEAF5F0), activeText: Color(0xFF2E7D5E),
      input: Color(0xFFF0F0F0), icon: Color(0xFF888888),
    ),
    AppThemeMode.dark: AppColors(
      bg: Color(0xFF18181B), sidebar: Color(0xFF1F1F23),
      card: Color(0xFF27272A), header: Color(0xFF1F1F23),
      text: Color(0xFFE8E8E8), subtext: Color(0xFF888888),
      accent: Color(0xFF3D9970), accentSoft: Color(0xFF1A3328),
      accentText: Color(0xFFFFFFFF), border: Color(0xFF323236),
      active: Color(0xFF1E3A2A), activeText: Color(0xFF4EAD87),
      input: Color(0xFF323236), icon: Color(0xFF888888),
    ),
    AppThemeMode.purple: AppColors(
      bg: Color(0xFFF7F5FB), sidebar: Color(0xFFFFFFFF),
      card: Color(0xFFFFFFFF), header: Color(0xFFFFFFFF),
      text: Color(0xFF1A1A2E), subtext: Color(0xFF9988BB),
      accent: Color(0xFF7C5CBF), accentSoft: Color(0xFFF0ECFA),
      accentText: Color(0xFFFFFFFF), border: Color(0xFFE8E2F5),
      active: Color(0xFFF0ECFA), activeText: Color(0xFF6644AA),
      input: Color(0xFFF0ECFA), icon: Color(0xFF9988BB),
    ),
    AppThemeMode.blue: AppColors(
      bg: Color(0xFFF4F7FB), sidebar: Color(0xFFFFFFFF),
      card: Color(0xFFFFFFFF), header: Color(0xFFFFFFFF),
      text: Color(0xFF1A2030), subtext: Color(0xFF7A95B8),
      accent: Color(0xFF3D72B4), accentSoft: Color(0xFFEAF0F9),
      accentText: Color(0xFFFFFFFF), border: Color(0xFFDCE8F5),
      active: Color(0xFFEAF0F9), activeText: Color(0xFF2D5A96),
      input: Color(0xFFEAF0F9), icon: Color(0xFF7A95B8),
    ),
    AppThemeMode.orange: AppColors(
      bg: Color(0xFFFDF8F4), sidebar: Color(0xFFFFFFFF),
      card: Color(0xFFFFFFFF), header: Color(0xFFFFFFFF),
      text: Color(0xFF1E1408), subtext: Color(0xFFB08060),
      accent: Color(0xFFD4722A), accentSoft: Color(0xFFFDF0E6),
      accentText: Color(0xFFFFFFFF), border: Color(0xFFF0DDD0),
      active: Color(0xFFFDF0E6), activeText: Color(0xFFB05A18),
      input: Color(0xFFFDF0E6), icon: Color(0xFFB08060),
    ),
    // ガラスモーフィズム: 濃い鮮やかな背景の上に白の半透明すりガラスパネル
    // 背景グラデーションは GlassBackground が描画する
    AppThemeMode.glass: AppColors(
      bg: Color(0x00000000), sidebar: Color(0x1FFFFFFF),
      card: Color(0x26FFFFFF), header: Color(0x1AFFFFFF),
      text: Color(0xFFFFFFFF), subtext: Color(0xB3FFFFFF),
      accent: Color(0xFF7C83FF), accentSoft: Color(0x40FFFFFF),
      accentText: Color(0xFFFFFFFF), border: Color(0x4DFFFFFF),
      active: Color(0x33FFFFFF), activeText: Color(0xFFFFFFFF),
      input: Color(0x26FFFFFF), icon: Color(0xD9FFFFFF),
      shadow: Color(0x40000000), shadowBlur: 24, blur: 20,
    ),
  };

  static AppColors of(AppThemeMode m) => themes[m]!;

  static ThemeData toMaterialTheme(AppThemeMode m) {
    final c = themes[m]!;
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: c.bg,
      fontFamily: 'NotoSansJP',
      colorScheme: ColorScheme(
        brightness: (m == AppThemeMode.dark || m == AppThemeMode.glass)
            ? Brightness.dark
            : Brightness.light,
        primary: c.accent, onPrimary: c.accentText,
        secondary: c.accent, onSecondary: c.accentText,
        // ガラスはダイアログ/メニューが透けないよう不透明面を使う
        surface: m == AppThemeMode.glass ? const Color(0xFF2A2656) : c.card,
        onSurface: c.text,
        error: Colors.red, onError: Colors.white,
      ),
    );
  }
}

/// ガラスモード用の背景（濃いグラデーション + 鮮やかな色の玉）
class GlassBackground extends StatelessWidget {
  final Widget child;
  const GlassBackground({super.key, required this.child});

  static Widget _blob(Color color, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withAlpha(0)]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // 暗い背景なのでステータスバーのアイコンを白にする
      value: SystemUiOverlayStyle.light,
      child: Stack(children: [
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1E1B4B),
                  Color(0xFF3B0764),
                  Color(0xFF0C4A6E),
                ],
              ),
            ),
          ),
        ),
        Positioned(top: -60, left: -80, child: _blob(const Color(0xE6EC4899), 340)),
        Positioned(top: 200, right: -100, child: _blob(const Color(0xCC8B5CF6), 340)),
        Positioned(bottom: -40, left: -20, child: _blob(const Color(0xB306B6D4), 320)),
        Positioned(bottom: 180, right: -30, child: _blob(const Color(0x99F97316), 240)),
        Positioned.fill(child: child),
      ]),
    );
  }
}

class ThemeNotifier extends ChangeNotifier {
  AppThemeMode _mode;
  AppThemeMode get mode => _mode;
  AppColors get colors => AppThemeData.of(_mode);

  ThemeNotifier(AppThemeMode initial) : _mode = initial;

  static Future<AppThemeMode> loadSaved() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/theme_preference.txt');
      if (await file.exists()) {
        final name = (await file.readAsString()).trim();
        return AppThemeMode.values.firstWhere(
          (m) => m.name == name,
          orElse: () => AppThemeMode.white,
        );
      }
    } catch (_) {}
    return AppThemeMode.white;
  }

  void setMode(AppThemeMode m) {
    _mode = m;
    notifyListeners();
    _save(m);
  }

  Future<void> _save(AppThemeMode m) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/theme_preference.txt');
      await file.writeAsString(m.name);
    } catch (_) {}
  }
}
