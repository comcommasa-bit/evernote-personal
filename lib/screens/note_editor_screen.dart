import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import '../app_theme.dart';
import '../database/db_helper.dart';
import '../models/note.dart';
import '../models/folder.dart';
import '../models/tag.dart';
import 'package:provider/provider.dart';

class NoteEditorScreen extends StatefulWidget {
  final Note note;
  final List<Folder> folders;
  final List<Tag> tags;
  final Function(Note) onSaved;

  const NoteEditorScreen({
    super.key,
    required this.note,
    required this.folders,
    required this.tags,
    required this.onSaved,
  });

  @override
  State<NoteEditorScreen> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditorScreen> {
  final _db = DbHelper();
  final _picker = ImagePicker();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _bodyCtrl;
  late Note _note;
  bool _changed = false;
  bool _isPreview = false;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _titleCtrl = TextEditingController(text: _note.title);
    _bodyCtrl = TextEditingController(text: _note.body);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final updated = _note.copyWith(
      title: _titleCtrl.text,
      body: _bodyCtrl.text,
      updatedAt: DateTime.now(),
    );
    await _db.updateNote(updated);
    _note = updated;
    _changed = false;
    widget.onSaved(updated);
  }

  // ────────────── ツールバー ──────────────

  void _applyMarkdown(String prefix, String suffix) {
    final text = _bodyCtrl.text;
    final sel = _bodyCtrl.selection;
    if (!sel.isValid) {
      final insert = '$prefix$suffix';
      _bodyCtrl.value = TextEditingValue(
        text: text + insert,
        selection: TextSelection.collapsed(offset: text.length + prefix.length),
      );
    } else {
      final selected = sel.textInside(text);
      final replaced = '$prefix$selected$suffix';
      final newText = text.replaceRange(sel.start, sel.end, replaced);
      _bodyCtrl.value = TextEditingValue(
        text: newText,
        selection:
            TextSelection.collapsed(offset: sel.start + replaced.length),
      );
    }
    setState(() => _changed = true);
  }

  void _applyLinePrefix(String prefix) {
    final text = _bodyCtrl.text;
    final sel = _bodyCtrl.selection;
    final pos = sel.isValid ? sel.baseOffset : text.length;
    final lineStart = text.lastIndexOf('\n', pos - 1) + 1;
    final newText =
        text.substring(0, lineStart) + prefix + text.substring(lineStart);
    _bodyCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: pos + prefix.length),
    );
    setState(() => _changed = true);
  }

  // ────────────── 画像 ──────────────

  Future<String?> _saveImage(String srcPath) async {
    final dir = await getApplicationDocumentsDirectory();
    final dest = p.join(dir.path, 'images', p.basename(srcPath));
    await Directory(p.dirname(dest)).create(recursive: true);
    await File(srcPath).copy(dest);
    return dest;
  }

  void _insertImagePath(String path) {
    final text = _bodyCtrl.text;
    final sel = _bodyCtrl.selection;
    final insert = '![]($path)\n';
    final pos = sel.isValid ? sel.baseOffset : text.length;
    final newText = text.substring(0, pos) + insert + text.substring(pos);
    _bodyCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: pos + insert.length),
    );
    setState(() {
      _note = _note.copyWith(imagePaths: [..._note.imagePaths, path]);
      _changed = true;
    });
  }

  Future<void> _pickImage() async {
    final c = context.read<ThemeNotifier>().colors;
    await showModalBottomSheet(
      context: context,
      backgroundColor: c.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(Icons.camera_alt_outlined, color: c.icon),
            title: Text('カメラで撮影', style: TextStyle(color: c.text)),
            onTap: () async {
              Navigator.pop(context);
              final status = await Permission.camera.request();
              if (!status.isGranted) return;
              final xf = await _picker.pickImage(
                  source: ImageSource.camera, imageQuality: 85);
              if (xf == null) return;
              final dest = await _saveImage(xf.path);
              if (dest != null) _insertImagePath(dest);
            },
          ),
          ListTile(
            leading: Icon(Icons.photo_library_outlined, color: c.icon),
            title: Text('ギャラリーから選択', style: TextStyle(color: c.text)),
            onTap: () async {
              Navigator.pop(context);
              final xf = await _picker.pickImage(
                  source: ImageSource.gallery, imageQuality: 85);
              if (xf == null) return;
              final dest = await _saveImage(xf.path);
              if (dest != null) _insertImagePath(dest);
            },
          ),
          ListTile(
            leading: Icon(Icons.folder_open_outlined, color: c.icon),
            title: Text('ファイルから選択', style: TextStyle(color: c.text)),
            onTap: () async {
              Navigator.pop(context);
              final result = await FilePicker.platform.pickFiles(
                type: FileType.image,
                allowMultiple: false,
              );
              if (result == null || result.files.single.path == null) return;
              final dest = await _saveImage(result.files.single.path!);
              if (dest != null) _insertImagePath(dest);
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _removeImage(String path) async {
    setState(() {
      _note = _note.copyWith(
          imagePaths: _note.imagePaths.where((e) => e != path).toList());
      _changed = true;
    });
  }

  Future<void> _softDelete() async {
    await _db.softDeleteNote(_note.id);
    if (!mounted) return;
    widget.onSaved(_note);
    Navigator.pop(context);
  }

  String _tagName(String id) => widget.tags
      .firstWhere((t) => t.id == id, orElse: () => const Tag(id: '', name: ''))
      .name;

  String _folderName(String id) => widget.folders
      .firstWhere((f) => f.id == id,
          orElse: () => const Folder(id: '', name: ''))
      .name;

  Widget _tbBtn(IconData icon, VoidCallback onTap) {
    final c = context.read<ThemeNotifier>().colors;
    return IconButton(
      icon: Icon(icon, size: 18, color: c.icon),
      onPressed: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      constraints: const BoxConstraints(),
    );
  }

  @override
  Widget build(BuildContext ctx) {
    final c = ctx.watch<ThemeNotifier>().colors;
    String fmtDate(DateTime d) =>
        '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_changed) await _save();
        if (mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: c.card,
        appBar: AppBar(
          backgroundColor: c.header,
          elevation: 0,
          iconTheme: IconThemeData(color: c.icon),
          title: Text(_folderName(_note.folderId),
              style: TextStyle(fontSize: 14, color: c.subtext)),
          actions: [
            if (_changed)
              TextButton(
                onPressed: _save,
                child: Text('保存',
                    style: TextStyle(
                        color: c.accent, fontWeight: FontWeight.w700)),
              ),
            IconButton(
              icon: Icon(
                _isPreview ? Icons.edit_outlined : Icons.preview_outlined,
                color: c.icon,
              ),
              tooltip: _isPreview ? '編集モード' : 'プレビュー',
              onPressed: () => setState(() => _isPreview = !_isPreview),
            ),
            IconButton(
              icon: Icon(
                  _note.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: _note.isPinned ? c.accent : c.icon),
              onPressed: () => setState(() {
                _note = _note.copyWith(isPinned: !_note.isPinned);
                _changed = true;
              }),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: c.icon),
              onSelected: (v) {
                if (v == 'delete') _softDelete();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      const Icon(Icons.delete_outline,
                          size: 16, color: Colors.red),
                      const SizedBox(width: 8),
                      Text('ゴミ箱へ', style: TextStyle(color: c.text)),
                    ])),
              ],
            ),
          ],
        ),
        body: Column(children: [
          Divider(height: 1, color: c.border),

          // タイトル
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: TextField(
              controller: _titleCtrl,
              onChanged: (_) => setState(() => _changed = true),
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700, color: c.text),
              decoration: InputDecoration(
                hintText: 'タイトル',
                hintStyle: TextStyle(
                    color: c.subtext,
                    fontWeight: FontWeight.w700,
                    fontSize: 22),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),

          // メタ情報
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
            child: Row(children: [
              PopupMenuButton<String>(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: c.input, borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.folder_outlined, size: 12, color: c.icon),
                    const SizedBox(width: 4),
                    Text(_folderName(_note.folderId),
                        style: TextStyle(fontSize: 11, color: c.subtext)),
                  ]),
                ),
                onSelected: (id) => setState(() {
                  _note = _note.copyWith(folderId: id);
                  _changed = true;
                }),
                itemBuilder: (_) => widget.folders
                    .map((f) => PopupMenuItem(
                        value: f.id,
                        child: Text(f.name,
                            style: TextStyle(fontSize: 13, color: c.text))))
                    .toList(),
              ),
              const SizedBox(width: 8),
              Icon(Icons.access_time, size: 10, color: c.subtext),
              const SizedBox(width: 2),
              Text('作成 ${fmtDate(_note.createdAt)}',
                  style: TextStyle(fontSize: 10, color: c.subtext)),
              const SizedBox(width: 6),
              Icon(Icons.update, size: 10, color: c.accent),
              const SizedBox(width: 2),
              Text('更新 ${fmtDate(_note.updatedAt)}',
                  style: TextStyle(
                      fontSize: 10, color: c.accent.withValues(alpha: 0.8))),
            ]),
          ),

          // タグ
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Wrap(spacing: 6, runSpacing: 4, children: [
              ..._note.tagIds.map((id) => GestureDetector(
                    onTap: () => setState(() {
                      _note = _note.copyWith(
                          tagIds: _note.tagIds.where((t) => t != id).toList());
                      _changed = true;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 2),
                      decoration: BoxDecoration(
                          color: c.accentSoft,
                          borderRadius: BorderRadius.circular(20)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('#${_tagName(id)}',
                            style: TextStyle(
                                fontSize: 11,
                                color: c.accent,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(width: 3),
                        Icon(Icons.close, size: 10, color: c.accent),
                      ]),
                    ),
                  )),
              PopupMenuButton<String>(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      border: Border.all(color: c.border),
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add, size: 11, color: c.subtext),
                    const SizedBox(width: 2),
                    Text('タグ追加',
                        style: TextStyle(fontSize: 11, color: c.subtext)),
                  ]),
                ),
                onSelected: (id) {
                  if (!_note.tagIds.contains(id)) {
                    setState(() {
                      _note = _note.copyWith(tagIds: [..._note.tagIds, id]);
                      _changed = true;
                    });
                  }
                },
                itemBuilder: (_) => widget.tags
                    .map((t) => PopupMenuItem(
                        value: t.id,
                        child: Text(t.name,
                            style: TextStyle(fontSize: 13, color: c.text))))
                    .toList(),
              ),
            ]),
          ),

          Divider(height: 1, color: c.border),

          // ツールバー
          Container(
            height: 40,
            color: c.card,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              _tbBtn(Icons.format_bold, () => _applyMarkdown('**', '**')),
              _tbBtn(Icons.format_italic, () => _applyMarkdown('*', '*')),
              _tbBtn(Icons.format_underline, () => _applyMarkdown('__', '__')),
              _tbBtn(Icons.format_list_bulleted, () => _applyLinePrefix('- ')),
              _tbBtn(Icons.format_list_numbered, () => _applyLinePrefix('1. ')),
              const Spacer(),
              _tbBtn(Icons.image_outlined, _pickImage),
            ]),
          ),
          Divider(height: 1, color: c.border),

          // 本文
          Expanded(
            child: _isPreview
                ? Markdown(
                    data: _bodyCtrl.text,
                    selectable: true,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(fontSize: 15, color: c.text, height: 1.8),
                      h1: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: c.text),
                      h2: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: c.text),
                      h3: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: c.text),
                      strong: TextStyle(
                          fontWeight: FontWeight.bold, color: c.text),
                      em: TextStyle(
                          fontStyle: FontStyle.italic, color: c.text),
                      blockquoteDecoration: BoxDecoration(
                        border: Border(
                            left: BorderSide(color: c.accent, width: 4)),
                        color: c.accentSoft,
                      ),
                      code: TextStyle(
                        backgroundColor: c.input,
                        color: c.accent,
                        fontFamily: 'monospace',
                      ),
                    ),
                  )
                : TextField(
                    controller: _bodyCtrl,
                    onChanged: (_) => setState(() => _changed = true),
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: TextStyle(fontSize: 15, color: c.text, height: 1.8),
                    decoration: InputDecoration(
                      hintText: 'メモを入力...',
                      hintStyle: TextStyle(color: c.subtext, fontSize: 15),
                      border: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    ),
                  ),
          ),

          // 画像サムネイル
          if (_note.imagePaths.isNotEmpty)
            Container(
              height: 90,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _note.imagePaths
                    .map((path) => Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Stack(children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(File(path),
                                  width: 100, height: 74, fit: BoxFit.cover),
                            ),
                            Positioned(
                              top: -4,
                              right: -4,
                              child: GestureDetector(
                                onTap: () => _removeImage(path),
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                      color: c.accent, shape: BoxShape.circle),
                                  child: const Icon(Icons.close,
                                      size: 12, color: Colors.white),
                                ),
                              ),
                            ),
                          ]),
                        ))
                    .toList(),
              ),
            ),

          // 画像追加ボタン
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                  border: Border.all(color: c.border, width: 1.5),
                  borderRadius: BorderRadius.circular(10)),
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.add_photo_alternate_outlined,
                    size: 16, color: c.icon),
                const SizedBox(width: 6),
                Text('画像を追加',
                    style: TextStyle(fontSize: 12, color: c.subtext)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
