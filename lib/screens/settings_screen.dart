import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../app_theme.dart';
import '../database/db_helper.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _db      = DbHelper();
  final _storage = const FlutterSecureStorage();

  // ── テーマ切り替え ─────────────────────────
  Widget _buildThemeSection(AppColors c, ThemeNotifier notifier) {
    const labels = {
      AppThemeMode.white:  'ホワイト',
      AppThemeMode.dark:   'ダーク',
      AppThemeMode.purple: 'パープル',
      AppThemeMode.blue:   'ブルー',
      AppThemeMode.orange: 'オレンジ',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Text('テーマ', style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: c.text)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 10, runSpacing: 10, children:
            AppThemeMode.values.map((mode) {
              final colors = AppThemeData.of(mode);
              final isActive = notifier.mode == mode;
              return GestureDetector(
                onTap: () => notifier.setMode(mode),
                child: Container(
                  width: 60, height: 72,
                  decoration: BoxDecoration(
                    color: colors.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isActive ? colors.accent : c.border,
                      width: isActive ? 2.5 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 24, height: 24,
                        decoration: BoxDecoration(
                          color: colors.accent, shape: BoxShape.circle),
                      ),
                      const SizedBox(height: 6),
                      Text(labels[mode]!, style: TextStyle(
                        fontSize: 9, color: colors.text,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.normal)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ── パスワード変更 ─────────────────────────
  Future<void> _changePassword(AppColors c) async {
    final currentCtrl = TextEditingController();
    final newCtrl     = TextEditingController();
    final confirmCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        title: Text('パスワード変更', style: TextStyle(fontSize: 16, color: c.text)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _pwField(currentCtrl, 'パスワードを入力', c),
          const SizedBox(height: 10),
          _pwField(newCtrl, '新しいパスワード', c),
          const SizedBox(height: 10),
          _pwField(confirmCtrl, '新しいパスワード（確認）', c),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('キャンセル', style: TextStyle(color: c.subtext)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: c.accent, foregroundColor: c.accentText),
            onPressed: () async {
              final saved = await _storage.read(key: 'app_password');
              if (saved != null && saved != currentCtrl.text) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('現在のパスワードが違います')));
                return;
              }
              if (newCtrl.text.isEmpty) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('新しいパスワードを入力してください')));
                return;
              }
              if (newCtrl.text != confirmCtrl.text) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('確認パスワードが一致しません')));
                return;
              }
              await _storage.write(key: 'app_password', value: newCtrl.text);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('パスワードを変更しました')));
            },
            child: const Text('変更'),
          ),
        ],
      ),
    );
  }

  Widget _pwField(TextEditingController ctrl, String hint, AppColors c) {
    return TextField(
      controller: ctrl, obscureText: true,
      style: TextStyle(fontSize: 14, color: c.text),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: c.subtext, fontSize: 13),
        filled: true, fillColor: c.input,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.border)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      ),
    );
  }

  // ── エクスポート ───────────────────────────
  Future<void> _export(AppColors c) async {
    try {
      final data = await _db.exportAll();
      final json = const JsonEncoder.withIndent('  ').convert(data);
      final dir  = await getApplicationDocumentsDirectory();
      final ts   = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final file = File('${dir.path}/evernote_backup_$ts.json');
      await file.writeAsString(json);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エクスポート完了: ${file.path}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エクスポート失敗: $e')));
    }
  }

  // ── インポート ───────────────────────────
  Future<void> _import(AppColors c) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['json']);
      if (result == null || result.files.single.path == null) return;

      final file = File(result.files.single.path!);
      final json = await file.readAsString();
      final data = jsonDecode(json) as Map<String, dynamic>;
      await _db.importAll(data);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('インポート完了')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('インポート失敗: $e')));
    }
  }

  // ── Build ──────────────────────────────────
  @override
  Widget build(BuildContext ctx) {
    final notifier = ctx.watch<ThemeNotifier>();
    final c = notifier.colors;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.header,
        elevation: 0,
        iconTheme: IconThemeData(color: c.icon),
        title: Text('設定', style: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
      ),
      body: ListView(children: [
        // テーマ
        _buildThemeSection(c, notifier),

        Divider(height: 32, color: c.border),

        // パスワード変更
        _settingsTile(
          c: c,
          icon: Icons.lock_outline,
          label: 'パスワード変更',
          onTap: () => _changePassword(c),
        ),

        Divider(height: 1, indent: 20, endIndent: 20, color: c.border),

        // エクスポート
        _settingsTile(
          c: c,
          icon: Icons.upload_outlined,
          label: 'データエクスポート（JSON）',
          onTap: () => _export(c),
        ),

        Divider(height: 1, indent: 20, endIndent: 20, color: c.border),

        // インポート
        _settingsTile(
          c: c,
          icon: Icons.download_outlined,
          label: 'データインポート（JSON）',
          onTap: () => _import(c),
        ),

        const SizedBox(height: 40),

        // バージョン
        Center(child: Text('Evernote-personal v1.0.0',
          style: TextStyle(fontSize: 11, color: c.subtext))),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _settingsTile({
    required AppColors c,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Icon(icon, size: 20, color: c.icon),
      title: Text(label, style: TextStyle(fontSize: 14, color: c.text)),
      trailing: Icon(Icons.chevron_right, size: 18, color: c.subtext),
      onTap: onTap,
    );
  }
}
