import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_theme.dart';
import 'database/db_helper.dart';
import 'screens/lock_screen.dart';
import 'screens/home_screen.dart';
import 'screens/setup_screen.dart';
import 'services/auth_service.dart';

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
  Widget build(BuildContext context) {
    final themeNotifier = context.watch<ThemeNotifier>();
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
  final _auth = AuthService();

  /// アプリの状態
  /// 'loading'  : 初期確認中
  /// 'setup'    : 初回セットアップ
  /// 'locked'   : ロック画面
  /// 'unlocked' : ホーム画面
  String _state = 'loading';

  /// バックグラウンド移行した時刻
  DateTime? _pausedAt;

  /// ロックまでの猶予時間（分）
  static const int _lockGraceMinutes = 5;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _init() async {
    // 30日経過ゴミ箱ノートを起動時に自動削除
    await DbHelper().deleteExpiredNotes();

    final hasPassword = await _auth.hasPassword();
    if (!mounted) return;
    setState(() => _state = hasPassword ? 'locked' : 'setup');
  }

  /// バックグラウンド/フォアグラウンド検知
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (_state == 'unlocked') {
        _pausedAt = DateTime.now();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_state == 'unlocked' && _pausedAt != null) {
        final elapsed = DateTime.now().difference(_pausedAt!);
        if (elapsed.inMinutes >= _lockGraceMinutes) {
          // 猶予時間を超えたらロック
          setState(() => _state = 'locked');
        }
        _pausedAt = null;
      }
    }
  }

  void _onSetupComplete() {
    setState(() => _state = 'locked');
  }

  void _onUnlocked() {
    _pausedAt = null;
    setState(() => _state = 'unlocked');
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case 'setup':
        return SetupScreen(onSetupComplete: _onSetupComplete);
      case 'locked':
        return LockScreen(onUnlocked: _onUnlocked);
      case 'unlocked':
        return const HomeScreen();
      default:
        // loading
        return const Scaffold(
          backgroundColor: Color(0xFFF0EEEA),
          body: Center(child: CircularProgressIndicator()),
        );
    }
  }
}
