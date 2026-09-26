import 'package:flutter/material.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../services/onenote_service.dart';

/// OneNote のセクションを選んでノートとして取り込む画面
class OneNoteScreen extends StatefulWidget {
  const OneNoteScreen({super.key});

  @override
  State<OneNoteScreen> createState() => _OneNoteScreenState();
}

class _OneNoteScreenState extends State<OneNoteScreen> {
  final _service = OneNoteService();
  bool _loading = true;
  bool _signedIn = false;
  String? _error;
  List<OneNoteItem> _notebooks = [];
  final Map<String, List<OneNoteItem>> _sections = {};
  bool _imported = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final signedIn = await _service.isSignedIn();
    setState(() => _signedIn = signedIn);
    if (signedIn) {
      await _loadNotebooks();
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadNotebooks() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _service.notebooks();
      setState(() => _notebooks = list);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signIn() async {
    try {
      await _service.signIn();
      setState(() => _signedIn = true);
      await _loadNotebooks();
    } on FlutterAppAuthUserCancelledException {
      // ユーザーがキャンセル
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('サインインに失敗しました: $e')));
    }
  }

  Future<void> _signOut() async {
    await _service.signOut();
    setState(() {
      _signedIn = false;
      _notebooks = [];
      _sections.clear();
    });
  }

  Future<void> _loadSections(String notebookId) async {
    if (_sections.containsKey(notebookId)) return;
    try {
      final list = await _service.sections(notebookId);
      setState(() => _sections[notebookId] = list);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('セクションの取得に失敗しました: $e')));
    }
  }

  Future<void> _import(OneNoteItem section) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('取り込み'),
        content: Text('「${section.name}」の全ページを取り込みます。\n'
            '同じ名前のフォルダに入ります（無ければ作成）。\n'
            '以前に取り込んだページは上書きされます。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('取り込む')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final progress = ValueNotifier<String>('ページ一覧を取得中…');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: progress,
                builder: (_, v, __) => Text(v),
              ),
            ),
          ]),
        ),
      ),
    );

    String message;
    try {
      final r = await _service.importSection(section,
          onProgress: (done, total) =>
              progress.value = '取り込み中… $done / $total ページ');
      _imported = true;
      message = 'ノート ${r.notes} 件、画像 ${r.images} 枚を取り込みました';
    } catch (e) {
      message = '取り込みに失敗しました: $e';
    }
    if (!mounted) return;
    Navigator.pop(context); // 進捗ダイアログを閉じる
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeNotifier>().colors;
    final textStyle =
        TextStyle(fontFamily: 'NotoSansJP', fontSize: 14, color: c.text);

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (!_signedIn) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Microsoft アカウントでサインインすると、\nOneNote のページを取り込めます。',
                textAlign: TextAlign.center, style: textStyle),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _signIn,
              icon: const Icon(Icons.login),
              label: const Text('Microsoft でサインイン'),
            ),
          ]),
        ),
      );
    } else if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center, style: textStyle),
            const SizedBox(height: 16),
            TextButton(onPressed: _loadNotebooks, child: const Text('再読み込み')),
          ]),
        ),
      );
    } else if (_notebooks.isEmpty) {
      body = Center(child: Text('ノートブックがありません', style: textStyle));
    } else {
      body = ListView(
        children: _notebooks
            .map((nb) => ExpansionTile(
                  leading: Icon(Icons.book_outlined, color: c.icon),
                  title: Text(nb.name, style: textStyle),
                  iconColor: c.icon,
                  collapsedIconColor: c.icon,
                  onExpansionChanged: (open) {
                    if (open) _loadSections(nb.id);
                  },
                  children: _sections[nb.id] == null
                      ? [
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(),
                          )
                        ]
                      : _sections[nb.id]!.isEmpty
                          ? [
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text('セクションがありません',
                                    style: textStyle),
                              )
                            ]
                          : _sections[nb.id]!
                              .map((s) => ListTile(
                                    contentPadding: const EdgeInsets.only(
                                        left: 32, right: 12),
                                    leading: Icon(Icons.folder_outlined,
                                        color: c.icon),
                                    title: Text(s.name, style: textStyle),
                                    trailing: TextButton(
                                      onPressed: () => _import(s),
                                      child: const Text('取り込む'),
                                    ),
                                  ))
                              .toList(),
                ))
            .toList(),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _imported);
      },
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          backgroundColor: c.header,
          foregroundColor: c.text,
          title: Text('OneNote から取り込む',
              style: TextStyle(
                  fontFamily: 'NotoSansJP',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: c.text)),
          actions: [
            if (_signedIn)
              TextButton(
                onPressed: _signOut,
                child: Text('サインアウト',
                    style: TextStyle(fontFamily: 'NotoSansJP', color: c.text)),
              ),
          ],
        ),
        body: body,
      ),
    );
  }
}
