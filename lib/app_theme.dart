import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum AppThemeMode { white, dark, purple, blue, orange }

class AppColors {
  final Color bg, sidebar, card, header, text, subtext;
  final Color accent, accentSoft, accentText;
  final Color border, active, activeText, input, icon;

  const AppColors({
    required this.bg, required this.sidebar, required this.card,
    required this.header, required this.text, required this.subtext,
    required this.accent, required this.accentSoft, required this.accentText,
    required this.border, required this.active, required this.activeText,
    required this.input, required this.icon,
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
  };

  static AppColors of(AppThemeMode m) => themes[m]!;

  static ThemeData toMaterialTheme(AppThemeMode m) {
    final c = themes[m]!;
    final baseTextTheme = GoogleFonts.notoSansJpTextTheme();
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: c.bg,
      colorScheme: ColorScheme(
        brightness: m == AppThemeMode.dark ? Brightness.dark : Brightness.light,
        primary: c.accent, onPrimary: c.accentText,
        secondary: c.accent, onSecondary: c.accentText,
        surface: c.card, onSurface: c.text,
        error: Colors.red, onError: Colors.white,
      ),
      textTheme: baseTextTheme.apply(
        bodyColor: c.text,
        displayColor: c.text,
      ),
      fontFamily: GoogleFonts.notoSansJp().fontFamily,
    );
  }
}

class ThemeNotifier extends ChangeNotifier {
  AppThemeMode _mode = AppThemeMode.white;
  AppThemeMode get mode => _mode;
  AppColors get colors => AppThemeData.of(_mode);

  void setMode(AppThemeMode m) {
    _mode = m;
    notifyListeners();
  }
}
