import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_theme.dart';
import 'screens/lock_screen.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeNotifier(),
      child: const App(),
    ),
  );
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext ctx) {
    final themeNotifier = ctx.watch<ThemeNotifier>();
    return MaterialApp(
      title: 'Evernote-personal',
      debugShowCheckedModeBanner: false,
      theme: AppThemeData.toMaterialTheme(themeNotifier.mode),
      home: const RootPage(),
    );
  }
}

class RootPage extends StatefulWidget {
  const RootPage({super.key});
  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> with WidgetsBindingObserver {
  bool _locked = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // バックグラウンド復帰時に再ロック
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      setState(() => _locked = true);
    }
  }

  @override
  Widget build(BuildContext ctx) {
    if (_locked) {
      return LockScreen(onUnlocked: () => setState(() => _locked = false));
    }
    return const HomeScreen();
  }
}
