import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
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

// ══════════════════════════════════════════
// ブロックモデル
// ══════════════════════════════════════════

enum BlockType { text, image, checkbox, numberedList }

enum TextSize { small, medium, large }

/// 画像表示サイズ
enum ImgSize { small, medium, large }

class NoteBlock {
  final String id;
  final BlockType type;
  String text;
  String? imagePath;
  bool checked;
  int listNumber;
  TextSize textSize;
  ImgSize imgSize;

  NoteBlock({
    required this.id,
    required this.type,
    this.text = '',
    this.imagePath,
    this.checked = false,
    this.listNumber = 1,
    this.textSize = TextSize.medium,
    this.imgSize = ImgSize.medium,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'text': text,
        'imagePath': imagePath,
        'checked': checked,
        'listNumber': listNumber,
        'textSize': textSize.name,
        'imgSize': imgSize.name,
      };

  static NoteBlock fromJson(Map<String, dynamic> j) => NoteBlock(
        id: j['id'] as String,
        type: BlockType.values.firstWhere((e) => e.name == j['type'],
            orElse: () => BlockType.text),
        text: j['text'] as String? ?? '',
        imagePath: j['imagePath'] as String?,
        checked: j['checked'] as bool? ?? false,
        listNumber: j['listNumber'] as int? ?? 1,
        textSize: TextSize.values.firstWhere(
            (e) => e.name == (j['textSize'] as String? ?? 'medium'),
            orElse: () => TextSize.medium),
        imgSize: ImgSize.values.firstWhere(
            (e) => e.name == (j['imgSize'] as String? ?? 'medium'),
            orElse: () => ImgSize.medium),
      );
}

// ══════════════════════════════════════════
// BlockSerializer
// ══════════════════════════════════════════
class BlockSerializer {
  static const _prefix = '[[BLOCKS]]';

  static String serialize(List<NoteBlock> blocks) {
    if (blocks.isEmpty) return '';
    return '$_prefix${jsonEncode(blocks.map((b) => b.toJson()).toList())}';
  }

  static List<NoteBlock> deserialize(String body) {
    if (!body.startsWith(_prefix)) {
      if (body.isEmpty) return [_newTextBlock()];
      return [
        NoteBlock(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          type: BlockType.text,
          text: body,
        )
      ];
    }
    try {
      final jsonStr = body.substring(_prefix.length);
      final list = jsonDecode(jsonStr) as List;
      final blocks = list
          .map((e) => NoteBlock.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      return blocks.isEmpty ? [_newTextBlock()] : blocks;
    } catch (_) {
      return [_newTextBlock()];
    }
  }

  static NoteBlock _newTextBlock() => NoteBlock(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: BlockType.text,
      );
}

// ══════════════════════════════════════════
// NoteEditorScreen
// ══════════════════════════════════════════

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
  late Note _note;
  late List<NoteBlock> _blocks;
  final Map<String, TextEditingController> _ctrlMap = {};
  final Map<String, FocusNode> _focusMap = {};

  bool _changed = false;
  bool _isNewNote = false;
  String? _focusedBlockId;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _titleCtrl = TextEditingController(text: _note.title);
    _isNewNote = _note.title.isEmpty &&
        _note.body.isEmpty &&
        _note.imagePaths.isEmpty;
    _blocks = BlockSerializer.deserialize(_note.body);
    _initControllers();
  }

  void _initControllers() {
    for (final b in _blocks) {
      _getCtrl(b);
      _getFocus(b);
    }
  }

  TextEditingController _getCtrl(NoteBlock b) {
    return _ctrlMap.putIfAbsent(
        b.id, () => TextEditingController(text: b.text));
  }

  FocusNode _getFocus(NoteBlock b) {
    return _focusMap.putIfAbsent(b.id, () {
      final fn = FocusNode();
      fn.addListener(() {
        if (fn.hasFocus && mounted) setState(() => _focusedBlockId = b.id);
      });
      return fn;
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    for (final c in _ctrlMap.values) c.dispose();
    for (final f in _focusMap.values) f.dispose();
    super.dispose();
  }

  // ── 保存 ───────────────────────────────
  Future<void> _save() async {
    for (final b in _blocks) {
      if (_ctrlMap.containsKey(b.id)) b.text = _ctrlMap[b.id]!.text;
    }
    final body = BlockSerializer.serialize(_blocks);
    final imagePaths = _blocks
        .where((b) => b.type == BlockType.image && b.imagePath != null)
        .map((b) => b.imagePath!)
        .toList();
    final updated = _note.copyWith(
      title: _titleCtrl.text,
      body: body,
      imagePaths: imagePaths,
      updatedAt: DateTime.now(),
    );
    await _db.updateNote(updated);
    _note = updated;
    _changed = false;
    widget.onSaved(updated);
  }

  // ── ブロック操作 ───────────────────────
  String _newId() =>
      '${DateTime.now().millisecondsSinceEpoch}_${_blocks.length}';

  void _addTextBlock({TextSize size = TextSize.medium}) {
    final b = NoteBlock(id: _newId(), type: BlockType.text, textSize: size);
    _insertAfterFocused(b);
    _focusAfterBuild(b.id);
  }

  void _addCheckbox() {
    final b = NoteBlock(id: _newId(), type: BlockType.checkbox);
    _insertAfterFocused(b);
    _focusAfterBuild(b.id);
  }

  /// 連番リスト追加。フォーカス中のブロックの後に追加し、番号を継続。
  void _addNumberedList() {
    // 現在のフォーカスブロックが連番なら続きの番号、そうでなければ末尾の最大値+1
    int nextNum = 1;
    if (_focusedBlockId != null) {
      final idx = _blocks.indexWhere((e) => e.id == _focusedBlockId);
      if (idx >= 0 && _blocks[idx].type == BlockType.numberedList) {
        nextNum = _blocks[idx].listNumber + 1;
        // 後続ブロックの番号を+1ずらす
        for (int i = idx + 1; i < _blocks.length; i++) {
          if (_blocks[i].type == BlockType.numberedList) {
            _blocks[i].listNumber++;
          }
        }
      } else {
        nextNum = _blocks
                .where((b) => b.type == BlockType.numberedList)
                .fold(0, (max, b) => b.listNumber > max ? b.listNumber : max) +
            1;
      }
    } else {
      nextNum = _blocks
              .where((b) => b.type == BlockType.numberedList)
              .fold(0, (max, b) => b.listNumber > max ? b.listNumber : max) +
          1;
    }
    final b = NoteBlock(
        id: _newId(), type: BlockType.numberedList, listNumber: nextNum);
    _insertAfterFocused(b);
    _focusAfterBuild(b.id);
  }

  void _insertAfterFocused(NoteBlock b) {
    setState(() {
      final idx = _focusedBlockId != null
          ? _blocks.indexWhere((e) => e.id == _focusedBlockId)
          : -1;
      _getCtrl(b);
      _getFocus(b);
      if (idx >= 0) {
        _blocks.insert(idx + 1, b);
      } else {
        _blocks.add(b);
      }
      _changed = true;
    });
  }

  void _focusAfterBuild(String id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusMap[id]?.requestFocus();
    });
  }

  void _removeBlock(String id) {
    setState(() {
      _blocks.removeWhere((b) => b.id == id);
      _ctrlMap.remove(id)?.dispose();
      _focusMap.remove(id)?.dispose();
      if (_blocks.isEmpty) {
        final b = NoteBlock(id: _newId(), type: BlockType.text);
        _blocks.add(b);
        _getCtrl(b);
        _getFocus(b);
      }
      _changed = true;
    });
  }

  void _toggleCheckbox(String id) {
    setState(() {
      final b = _blocks.firstWhere((e) => e.id == id);
      b.checked = !b.checked;
      _changed = true;
    });
  }

  void _changeTextSize(String id, TextSize size) {
    setState(() {
      final b = _blocks.firstWhere((e) => e.id == id);
      b.textSize = size;
      _changed = true;
    });
  }

  /// Enterキーで同種の次ブロックを自動追加
  void _onBlockSubmit(NoteBlock b) {
    switch (b.type) {
      case BlockType.checkbox:
        // テキストが空なら削除してテキストブロックに切り替え
        final text = _ctrlMap[b.id]?.text ?? '';
        if (text.isEmpty) {
          _removeBlock(b.id);
          _addTextBlock();
        } else {
          _addCheckbox();
        }
        break;
      case BlockType.numberedList:
        final text = _ctrlMap[b.id]?.text ?? '';
        if (text.isEmpty) {
          _removeBlock(b.id);
          _addTextBlock();
        } else {
          _addNumberedList();
        }
        break;
      default:
        // テキストブロックはデフォルトの改行動作に任せる
        break;
    }
  }

  // ── 画像 ───────────────────────────────
  Future<String?> _saveImageFile(String srcPath) async {
    final dir = await getApplicationDocumentsDirectory();
    final dest = p.join(dir.path, 'images', p.basename(srcPath));
    await Directory(p.dirname(dest)).create(recursive: true);
    await File(srcPath).copy(dest);
    return dest;
  }

  Future<void> _pickImage() async {
    final c = context.read<ThemeNotifier>().colors;
    await showModalBottomSheet(
      context: context,
      backgroundColor: c.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
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
              if (xf == null || !mounted) return;
              final dest = await _saveImageFile(xf.path);
              if (dest != null) _insertImageBlock(dest);
            },
          ),
          ListTile(
            leading: Icon(Icons.photo_library_outlined, color: c.icon),
            title: Text('ギャラリーから選択', style: TextStyle(color: c.text)),
            onTap: () async {
              Navigator.pop(context);
              final xf = await _picker.pickImage(
                  source: ImageSource.gallery, imageQuality: 85);
              if (xf == null || !mounted) return;
              final dest = await _saveImageFile(xf.path);
              if (dest != null) _insertImageBlock(dest);
            },
          ),
          ListTile(
            leading: Icon(Icons.folder_open_outlined, color: c.icon),
            title: Text('ファイルから選択', style: TextStyle(color: c.text)),
            onTap: () async {
              Navigator.pop(context);
              final result = await FilePicker.platform
                  .pickFiles(type: FileType.image, allowMultiple: false);
              if (result == null ||
                  result.files.single.path == null ||
                  !mounted) return;
              final dest =
                  await _saveImageFile(result.files.single.path!);
              if (dest != null) _insertImageBlock(dest);
            },
          ),
        ]),
      ),
    );
  }

  void _insertImageBlock(String path) {
    final imgBlock = NoteBlock(
        id: _newId(), type: BlockType.image, imagePath: path);
    final textBlock = NoteBlock(id: _newId(), type: BlockType.text);
    setState(() {
      final idx = _focusedBlockId != null
          ? _blocks.indexWhere((e) => e.id == _focusedBlockId)
          : -1;
      _getCtrl(imgBlock);
      _getFocus(imgBlock);
      _getCtrl(textBlock);
      _getFocus(textBlock);
      if (idx >= 0) {
        _blocks.insert(idx + 1, imgBlock);
        _blocks.insert(idx + 2, textBlock);
      } else {
        _blocks.add(imgBlock);
        _blocks.add(textBlock);
      }
      _changed = true;
    });
    _focusAfterBuild(textBlock.id);
  }

  void _changeImageSize(String id, ImgSize size) {
    setState(() {
      final b = _blocks.firstWhere((e) => e.id == id);
      b.imgSize = size;
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

  // ── BUILD ──────────────────────────────
  @override
  Widget build(BuildContext ctx) {
    final c = ctx.watch<ThemeNotifier>().colors;
    String fmtDate(DateTime d) =>
        '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        for (final b in _blocks) {
          if (_ctrlMap.containsKey(b.id)) b.text = _ctrlMap[b.id]!.text;
        }
        final title = _titleCtrl.text.trim();
        final hasContent = title.isNotEmpty ||
            _blocks.any((b) =>
                b.type == BlockType.image || b.text.isNotEmpty);
        if (_isNewNote && !hasContent) {
          await _db.hardDeleteNote(_note.id);
          widget.onSaved(_note);
        } else if (_changed) {
          await _save();
        }
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
                    color: c.subtext, fontWeight: FontWeight.w700, fontSize: 22),
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
                      fontSize: 10,
                      color: c.accent.withValues(alpha: 0.8))),
            ]),
          ),
          // タグ
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Wrap(spacing: 6, runSpacing: 4, children: [
              ..._note.tagIds.map((id) => GestureDetector(
                    onTap: () => setState(() {
                      _note = _note.copyWith(
                          tagIds:
                              _note.tagIds.where((t) => t != id).toList());
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
                      _note =
                          _note.copyWith(tagIds: [..._note.tagIds, id]);
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
          _buildToolbar(c),
          Divider(height: 1, color: c.border),
          // ブロックリスト
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
              itemCount: _blocks.length,
              itemBuilder: (_, i) => _buildBlock(_blocks[i], c),
            ),
          ),
        ]),
      ),
    );
  }

  // ── ツールバー ─────────────────────────
  Widget _buildToolbar(AppColors c) {
    return Container(
      height: 48,
      color: c.card,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          // テキストサイズ
          _tbBtn(c, Icons.text_decrease, '小文字',
              () => _addTextBlock(size: TextSize.small),
              label: '小'),
          _tbBtn(c, Icons.text_fields, '中文字',
              () => _addTextBlock(),
              label: '中'),
          _tbBtn(c, Icons.text_increase, '大文字',
              () => _addTextBlock(size: TextSize.large),
              label: '大'),
          _tbDivider(c),
          // チェック・連番
          _tbBtn(c, Icons.check_box_outlined, 'チェック', _addCheckbox),
          _tbBtn(c, Icons.format_list_numbered, '連番', _addNumberedList),
          _tbDivider(c),
          // 画像
          _tbBtn(c, Icons.image_outlined, '画像を追加', _pickImage),
        ]),
      ),
    );
  }

  Widget _tbDivider(AppColors c) => Container(
      width: 1, height: 24, color: c.border,
      margin: const EdgeInsets.symmetric(horizontal: 4));

  Widget _tbBtn(AppColors c, IconData icon, String tooltip, VoidCallback onTap,
      {String? label}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: label != null
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 18, color: c.icon),
                  Text(label,
                      style: TextStyle(
                          fontSize: 8,
                          color: c.subtext,
                          fontWeight: FontWeight.w600)),
                ])
              : Icon(icon, size: 20, color: c.icon),
        ),
      ),
    );
  }

  // ── ブロック描画 ───────────────────────
  Widget _buildBlock(NoteBlock b, AppColors c) {
    switch (b.type) {
      case BlockType.text:
        return _buildTextBlock(b, c);
      case BlockType.image:
        return _buildImageBlock(b, c);
      case BlockType.checkbox:
        return _buildCheckboxBlock(b, c);
      case BlockType.numberedList:
        return _buildNumberedBlock(b, c);
    }
  }

  Widget _buildTextBlock(NoteBlock b, AppColors c) {
    final ctrl = _getCtrl(b);
    final focus = _getFocus(b);
    final fontSize = _getFontSize(b.textSize);
    final isFocused = _focusedBlockId == b.id;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // フォーカス中はサイズ変更ボタンを表示
        if (isFocused)
          PopupMenuButton<TextSize>(
            icon: Icon(_textSizeIcon(b.textSize), size: 14, color: c.subtext),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onSelected: (size) => _changeTextSize(b.id, size),
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: TextSize.small,
                  child: Row(children: [
                    const Icon(Icons.text_decrease, size: 16),
                    const SizedBox(width: 8),
                    Text('小 (12px)', style: TextStyle(color: c.text)),
                  ])),
              PopupMenuItem(
                  value: TextSize.medium,
                  child: Row(children: [
                    const Icon(Icons.text_fields, size: 16),
                    const SizedBox(width: 8),
                    Text('中 (16px)', style: TextStyle(color: c.text)),
                  ])),
              PopupMenuItem(
                  value: TextSize.large,
                  child: Row(children: [
                    const Icon(Icons.text_increase, size: 16),
                    const SizedBox(width: 8),
                    Text('大 (22px)', style: TextStyle(color: c.text)),
                  ])),
            ],
          )
        else
          SizedBox(
              width: 28,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(_textSizeIcon(b.textSize),
                    size: 10, color: c.border),
              )),
        Expanded(
          child: TextField(
            controller: ctrl,
            focusNode: focus,
            onChanged: (_) => setState(() => _changed = true),
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            style:
                TextStyle(fontSize: fontSize, color: c.text, height: 1.6),
            decoration: InputDecoration(
              hintText: 'テキストを入力...',
              hintStyle:
                  TextStyle(color: c.subtext, fontSize: fontSize),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
            ),
          ),
        ),
        if (isFocused && _blocks.length > 1)
          GestureDetector(
            onTap: () => _removeBlock(b.id),
            child: Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Icon(Icons.close, size: 14, color: c.subtext),
            ),
          ),
      ]),
    );
  }

  Widget _buildCheckboxBlock(NoteBlock b, AppColors c) {
    final ctrl = _getCtrl(b);
    final focus = _getFocus(b);
    final isFocused = _focusedBlockId == b.id;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        GestureDetector(
          onTap: () => _toggleCheckbox(b.id),
          child: Icon(
            b.checked ? Icons.check_box : Icons.check_box_outline_blank,
            size: 22,
            color: b.checked ? c.accent : c.subtext,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: ctrl,
            focusNode: focus,
            onChanged: (_) => setState(() => _changed = true),
            onSubmitted: (_) => _onBlockSubmit(b),
            textInputAction: TextInputAction.next,
            style: TextStyle(
              fontSize: 15,
              color: b.checked ? c.subtext : c.text,
              decoration:
                  b.checked ? TextDecoration.lineThrough : null,
              height: 1.5,
            ),
            decoration: InputDecoration(
              hintText: 'チェック項目...',
              hintStyle: TextStyle(color: c.subtext, fontSize: 15),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
            ),
          ),
        ),
        if (isFocused)
          GestureDetector(
            onTap: () => _removeBlock(b.id),
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(Icons.close, size: 14, color: c.subtext),
            ),
          ),
      ]),
    );
  }

  Widget _buildNumberedBlock(NoteBlock b, AppColors c) {
    final ctrl = _getCtrl(b);
    final focus = _getFocus(b);
    final isFocused = _focusedBlockId == b.id;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 32,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('${b.listNumber}.',
                style: TextStyle(
                    fontSize: 15,
                    color: c.accent,
                    fontWeight: FontWeight.w600)),
          ),
        ),
        Expanded(
          child: TextField(
            controller: ctrl,
            focusNode: focus,
            onChanged: (_) => setState(() => _changed = true),
            onSubmitted: (_) => _onBlockSubmit(b),
            textInputAction: TextInputAction.next,
            style:
                TextStyle(fontSize: 15, color: c.text, height: 1.5),
            decoration: InputDecoration(
              hintText: 'リスト項目...',
              hintStyle: TextStyle(color: c.subtext, fontSize: 15),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
            ),
          ),
        ),
        if (isFocused)
          GestureDetector(
            onTap: () => _removeBlock(b.id),
            child: Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Icon(Icons.close, size: 14, color: c.subtext),
            ),
          ),
      ]),
    );
  }

  Widget _buildImageBlock(NoteBlock b, AppColors c) {
    if (b.imagePath == null) return const SizedBox.shrink();
    final file = File(b.imagePath!);
    final imgDims = _getImgDims(b.imgSize);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Stack(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: file.existsSync()
                ? Image.file(
                    file,
                    width: imgDims.width,
                    height: imgDims.height,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: imgDims.width ?? double.infinity,
                    height: imgDims.height ?? 160,
                    decoration: BoxDecoration(
                        color: c.input,
                        borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.broken_image_outlined,
                        color: c.subtext, size: 32),
                  ),
          ),
          // サイズ変更 & 削除ボタン（画像右上）
          Positioned(
            top: 6,
            right: 6,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _imgSizeBtn(c, '小', b.imgSize == ImgSize.small,
                  () => _changeImageSize(b.id, ImgSize.small)),
              const SizedBox(width: 3),
              _imgSizeBtn(c, '中', b.imgSize == ImgSize.medium,
                  () => _changeImageSize(b.id, ImgSize.medium)),
              const SizedBox(width: 3),
              _imgSizeBtn(c, '大', b.imgSize == ImgSize.large,
                  () => _changeImageSize(b.id, ImgSize.large)),
              const SizedBox(width: 5),
              GestureDetector(
                onTap: () => _removeBlock(b.id),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(6)),
                  child: const Icon(Icons.close, size: 12, color: Colors.white),
                ),
              ),
            ]),
          ),
        ]),
      ]),
    );
  }

  Widget _imgSizeBtn(
      AppColors c, String label, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
            color: isActive
                ? c.accent
                : c.accent.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(6)),
        child: Text(label,
            style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w900 : FontWeight.w500)),
      ),
    );
  }

  double _getFontSize(TextSize size) {
    switch (size) {
      case TextSize.small:
        return 12;
      case TextSize.medium:
        return 16;
      case TextSize.large:
        return 22;
    }
  }

  IconData _textSizeIcon(TextSize size) {
    switch (size) {
      case TextSize.small:
        return Icons.text_decrease;
      case TextSize.large:
        return Icons.text_increase;
      default:
        return Icons.text_fields;
    }
  }

  ({double? width, double? height}) _getImgDims(ImgSize size) {
    switch (size) {
      case ImgSize.small:
        return (width: 120.0, height: 90.0);
      case ImgSize.large:
        return (width: null, height: null);
      default: // medium
        return (width: 240.0, height: 180.0);
    }
  }
}
