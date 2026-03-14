import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../app_theme.dart';
import '../database/db_helper.dart';
import '../models/note.dart';
import '../models/folder.dart';
import '../models/tag.dart';
import '../services/upnote_importer.dart';
import 'note_editor_screen.dart';

const _uuid = Uuid();

/// ブロック形式のbodyからプレビュー用のプレーンテキストを抽出
String _extractBodyPreview(String body) {
  const prefix = '[[BLOCKS]]';
  if (!body.startsWith(prefix)) return body;
  try {
    final jsonStr = body.substring(prefix.length);
    final list = jsonDecode(jsonStr) as List;
    final parts = <String>[];
    for (final item in list) {
      final map = Map<String, dynamic>.from(item as Map);
      final type = map['type'] as String? ?? 'text';
      final text = map['text'] as String? ?? '';
      if (type == 'image') {
        parts.add('[画像]');
      } else if (type == 'checkbox') {
        final checked = map['checked'] as bool? ?? false;
        parts.add('${checked ? '[v]' : '[ ]'} $text');
      } else if (type == 'numberedList') {
        final num = map['listNumber'] as int? ?? 1;
        parts.add('$num. $text');
      } else if (text.isNotEmpty) {
        parts.add(text);
      }
    }
    return parts.join('  ');
  } catch (_) {
    return body;
  }
}

enum SortMode { updated, created, name, tag }

String _sortLabel(SortMode s) {
  switch (s) {
    case SortMode.updated:
      return '更新日';
    case SortMode.created:
      return '作成日';
    case SortMode.name:
      return '名前';
    case SortMode.tag:
      return 'タグ';
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _db = DbHelper();

  List<Folder> _folders = [];
  List<Tag> _tags = [];
  List<Note> _notes = [];

  String? _activeFolderId;
  String? _activeTagId;
  String _search = '';
  SortMode _sort = SortMode.updated;
  Note? _selected;
  bool _showTrash = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final f = await _db.getFolders();
    final t = await _db.getTags();
    final n = await _db.getNotes(includeDeleted: true);
    if (!mounted) return;
    setState(() {
      _folders = f;
      _tags = t;
      _notes = n;
    });
  }

  List<Note> get _filtered {
    var list = _notes.where((n) {
      if (_showTrash) return n.isDeleted;
      if (n.isDeleted) return false;
      final folderOk = _activeFolderId == null || n.folderId == _activeFolderId;
      final tagOk = _activeTagId == null || n.tagIds.contains(_activeTagId);
      final searchOk = _search.isEmpty ||
          n.title.contains(_search) ||
          n.body.contains(_search);
      return folderOk && tagOk && searchOk;
    }).toList();

    list.sort((a, b) {
      if (a.isPinned != b.isPinned) return b.isPinned ? 1 : -1;
      switch (_sort) {
        case SortMode.name:
          return a.title.compareTo(b.title);
        case SortMode.tag:
          return (a.tagIds.firstOrNull ?? '')
              .compareTo(b.tagIds.firstOrNull ?? '');
        case SortMode.created:
          return b.createdAt.compareTo(a.createdAt);
        case SortMode.updated:
          return b.updatedAt.compareTo(a.updatedAt);
      }
    });
    return list;
  }

  Future<void> _newNote() async {
    final now = DateTime.now();
    final note = Note(
      id: _uuid.v4(),
      folderId:
          _activeFolderId ?? (_folders.isNotEmpty ? _folders.first.id : ''),
      createdAt: now,
      updatedAt: now,
    );
    await _db.insertNote(note);
    await _load();
    if (!mounted) return;
    _openEditor(note);
  }

  void _openEditor(Note note) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => NoteEditorScreen(
                note: note,
                folders: _folders,
                tags: _tags,
                onSaved: (_) => _load(),
              )),
    );
    _load();
  }

  Future<void> _restoreNote(String id) async {
    await _db.restoreNote(id);
    _load();
  }

  Future<void> _hardDeleteNote(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('完全に削除'),
        content: const Text('このメモを完全に削除しますか？元に戻せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _db.hardDeleteNote(id);
      _load();
    }
  }

  Future<void> _emptyTrash() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ゴミ箱を空にする'),
        content: const Text(
            'ゴミ箱内のすべてのメモを完全に削除します。\nこの操作は取り消せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('すべて削除',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _db.emptyTrash();
      _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('ゴミ箱を空にしました')));
    }
  }

  Future<void> _exportData() async {
    final proceed = await _showTutorial(
      title: 'エクスポートとは？',
      icon: Icons.upload_outlined,
      steps: const [
        'ノート・フォルダ・タグをすべてJSONファイルに保存します。',
        '保存先はアプリ内ドキュメントフォルダです。',
        'バックアップや機種変更のデータ移行に使えます。',
        '「インポート」で同じ端末や別の端末に復元できます。',
      ],
      proceedLabel: 'エクスポートする',
    );
    if (proceed != true) return;
    try {
      final data = await _db.exportAll();
      final json = const JsonEncoder.withIndent('  ').convert(data);
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = '${dir.path}/evernote_backup_$ts.json';
      await File(path).writeAsString(json);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('エクスポート完了'),
          content: Text('保存先:\n$path'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('エクスポートに失敗しました: $e')));
    }
  }

  Future<void> _importUpNote() async {
    final proceed = await _showTutorial(
      title: 'UpNoteインポートとは？',
      icon: Icons.folder_zip_outlined,
      steps: const [
        'UpNoteのバックアップZIPファイルからノートを取り込みます。',
        'UpNoteアプリ → 設定 → バックアップ → 「エクスポート」でZIPを作成してください。',
        'ZIPの中にある .md（Markdown）ファイルを自動解析します。',
        'ノートブック名はフォルダとして、タグもそのまま引き継ぎます。',
        '画像ファイル（jpg/png/webp等）も自動でインポートされます。',
      ],
      proceedLabel: 'ZIPを選択する',
    );
    if (proceed != true) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (result == null || result.files.single.path == null) return;
      final result2 =
          await UpNoteImporter().importZip(result.files.single.path!);
      await _load();
      if (!mounted) return;
      final notes = result2['notes'] ?? 0;
      final images = result2['images'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('UpNoteから $notes 件、画像 $images 枚インポートしました')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('インポートに失敗しました: $e')));
    }
  }

  Future<void> _importData() async {
    final proceed = await _showTutorial(
      title: 'インポートとは？',
      icon: Icons.download_outlined,
      steps: const [
        'このアプリの「エクスポート」で作ったJSONファイルを読み込みます。',
        'フォルダ・タグ・ノートがすべて復元されます。',
        '既存のデータと重複する場合は上書きされます。',
        'ファイルマネージャーで保存先のJSONを選択してください。',
      ],
      proceedLabel: 'ファイルを選択する',
    );
    if (proceed != true) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.single.path == null) return;
      final file = File(result.files.single.path!);
      final json = await file.readAsString();
      final data = jsonDecode(json) as Map<String, dynamic>;
      await _db.importAll(data);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('インポートが完了しました')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('インポートに失敗しました: $e')));
    }
  }

  /// インポート/エクスポート共通チュートリアルダイアログ
  Future<bool?> _showTutorial({
    required String title,
    required IconData icon,
    required List<String> steps,
    required String proceedLabel,
  }) {
    final c = context.read<ThemeNotifier>().colors;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(icon, size: 22, color: c.accent),
          const SizedBox(width: 8),
          Expanded(
              child: Text(title,
                  style: GoogleFonts.notoSansJp(
                      fontSize: 16, fontWeight: FontWeight.w700))),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...steps.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        margin: const EdgeInsets.only(right: 8, top: 1),
                        decoration: BoxDecoration(
                            color: c.accent, shape: BoxShape.circle),
                        child: Center(
                          child: Text(
                            '${e.key + 1}',
                            style: GoogleFonts.notoSansJp(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      Expanded(
                          child: Text(e.value,
                              style: GoogleFonts.notoSansJp(
                                  fontSize: 13, color: c.text, height: 1.5))),
                    ],
                  ),
                )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(proceedLabel),
          ),
        ],
      ),
    );
  }

  void _showThemeSelector() {
    const labels = {
      AppThemeMode.white: 'ホワイト',
      AppThemeMode.dark: 'ダーク',
      AppThemeMode.purple: 'パープル',
      AppThemeMode.blue: 'ブルー',
      AppThemeMode.orange: 'オレンジ',
    };
    const themeColors = {
      AppThemeMode.white: Color(0xFF3D9970),
      AppThemeMode.dark: Color(0xFF555555),
      AppThemeMode.purple: Color(0xFF7C5CBF),
      AppThemeMode.blue: Color(0xFF3D72B4),
      AppThemeMode.orange: Color(0xFFD4722A),
    };
    showDialog(
      context: context,
      builder: (ctx) {
        final notifier = ctx.read<ThemeNotifier>();
        final current = notifier.mode;
        return AlertDialog(
          title: Text('テーマ', style: GoogleFonts.notoSansJp(fontSize: 16, fontWeight: FontWeight.w700)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: AppThemeMode.values.map((mode) {
              final isActive = mode == current;
              return InkWell(
                onTap: () {
                  notifier.setMode(mode);
                  Navigator.pop(ctx);
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isActive
                        ? (themeColors[mode]!).withOpacity(0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: isActive
                            ? themeColors[mode]!
                            : Colors.transparent,
                        width: 1.5),
                  ),
                  child: Row(children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: themeColors[mode],
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: themeColors[mode]!.withOpacity(0.4),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          )
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(labels[mode]!,
                            style: GoogleFonts.notoSansJp(
                                fontSize: 14,
                                fontWeight: isActive
                                    ? FontWeight.w700
                                    : FontWeight.normal))),
                    if (isActive)
                      Icon(Icons.check_circle,
                          size: 16, color: themeColors[mode]),
                  ]),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext ctx) {
    final c = ctx.watch<ThemeNotifier>().colors;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Row(children: [
          _Sidebar(
            colors: c,
            folders: _folders,
            tags: _tags,
            activeFolderId: _activeFolderId,
            activeTagId: _activeTagId,
            showTrash: _showTrash,
            onFolderTap: (id) => setState(() {
              _activeFolderId = id;
              _activeTagId = null;
              _showTrash = false;
            }),
            onTagTap: (id) => setState(() {
              _activeTagId = _activeTagId == id ? null : id;
              _activeFolderId = null;
              _showTrash = false;
            }),
            onTrashTap: () => setState(() {
              _showTrash = true;
              _activeFolderId = null;
              _activeTagId = null;
            }),
            onFoldersReordered: (f) async {
              _folders = f;
              await _db.reorderFolders(f);
              setState(() {});
            },
            onFolderAdded: (name) async {
              await _db.insertFolder(
                  Folder(id: _uuid.v4(), name: name, sortOrder: _folders.length));
              _load();
            },
            onFolderRenamed: (f) async {
              await _db.updateFolder(f);
              _load();
            },
            onTagAdded: (name) async {
              await _db.insertTag(Tag(id: _uuid.v4(), name: name));
              _load();
            },
            onTagRenamed: (t) async {
              await _db.updateTag(t);
              _load();
            },
            onNewNote: _newNote,
            onTheme: _showThemeSelector,
          ),
          _NoteList(
            colors: c,
            notes: _filtered,
            tags: _tags,
            selected: _selected,
            sort: _sort,
            search: _search,
            showTrash: _showTrash,
            onSearchChanged: (v) => setState(() => _search = v),
            onSortChanged: (s) => setState(() => _sort = s),
            onNoteTap: (n) {
              setState(() => _selected = n);
              _openEditor(n);
            },
            onNewNote: _newNote,
            count: _filtered.length,
            onRestoreNote: _restoreNote,
            onHardDeleteNote: _hardDeleteNote,
            onEmptyTrash: _emptyTrash,
            onExport: _exportData,
            onImport: _importData,
            onImportUpNote: _importUpNote,
          ),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════
// Sidebar  (redesigned – narrower, icons, theme at bottom)
// ══════════════════════════════════════════
class _Sidebar extends StatefulWidget {
  final AppColors colors;
  final List<Folder> folders;
  final List<Tag> tags;
  final String? activeFolderId;
  final String? activeTagId;
  final bool showTrash;
  final Function(String?) onFolderTap;
  final Function(String) onTagTap;
  final VoidCallback onTrashTap;
  final Function(List<Folder>) onFoldersReordered;
  final Function(String) onFolderAdded;
  final Function(Folder) onFolderRenamed;
  final Function(String) onTagAdded;
  final Function(Tag) onTagRenamed;
  final VoidCallback onNewNote;
  final VoidCallback onTheme;

  const _Sidebar({
    required this.colors,
    required this.folders,
    required this.tags,
    required this.activeFolderId,
    required this.activeTagId,
    required this.showTrash,
    required this.onFolderTap,
    required this.onTagTap,
    required this.onTrashTap,
    required this.onFoldersReordered,
    required this.onFolderAdded,
    required this.onFolderRenamed,
    required this.onTagAdded,
    required this.onTagRenamed,
    required this.onNewNote,
    required this.onTheme,
  });

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  String? _editingFolderId;
  String? _editingTagId;
  bool _addingFolder = false;
  bool _addingTag = false;

  AppColors get c => widget.colors;

  @override
  Widget build(BuildContext ctx) {
    return Container(
      width: 165,
      decoration: BoxDecoration(
        color: c.sidebar,
        border: Border(right: BorderSide(color: c.border, width: 1)),
      ),
      child: Column(children: [
        // ─── Header ─────────────────────────────
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Image.asset('assets/images/hippo.png', width: 24, height: 24),
            const SizedBox(width: 8),
            Expanded(
                child: Text('Evernote',
                    style: GoogleFonts.notoSansJp(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: c.text))),
          ]),
        ),
        Divider(height: 1, color: c.border),

        // ─── New note button ─────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: widget.onNewNote,
              style: ElevatedButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: c.accentText,
                padding: const EdgeInsets.symmetric(vertical: 9),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9)),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add, size: 15),
                  const SizedBox(width: 4),
                  Text('新規メモ',
                      style: GoogleFonts.notoSansJp(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),

        Expanded(
          child: ListView(padding: EdgeInsets.zero, children: [
            // ─ すべてのメモ ─
            _NavTile(
              c: c,
              icon: Icons.notes,
              label: 'すべてのメモ',
              isActive: widget.activeFolderId == null &&
                  !widget.showTrash &&
                  widget.activeTagId == null,
              onTap: () => widget.onFolderTap(null),
            ),

            // ─ フォルダ ─
            _SectionHeader(
                c: c,
                label: 'フォルダ',
                onAdd: () => setState(() => _addingFolder = true)),

            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              onReorder: (o, n) {
                final list = [...widget.folders];
                if (n > o) n--;
                final item = list.removeAt(o);
                list.insert(n, item);
                widget.onFoldersReordered(list);
              },
              children: widget.folders.map((f) {
                if (_editingFolderId == f.id) {
                  return _EditTile(
                    key: ValueKey(f.id),
                    c: c,
                    initialValue: f.name,
                    onConfirm: (v) {
                      widget.onFolderRenamed(
                          Folder(id: f.id, name: v, sortOrder: f.sortOrder));
                      setState(() => _editingFolderId = null);
                    },
                    onCancel: () => setState(() => _editingFolderId = null),
                  );
                }
                return _NavTile(
                  key: ValueKey(f.id),
                  c: c,
                  icon: Icons.folder_outlined,
                  label: f.name,
                  isActive: widget.activeFolderId == f.id,
                  draggable: true,
                  onTap: () => widget.onFolderTap(f.id),
                  onEdit: () => setState(() => _editingFolderId = f.id),
                );
              }).toList(),
            ),

            if (_addingFolder)
              _EditTile(
                key: const ValueKey('new_folder'),
                c: c,
                initialValue: '',
                onConfirm: (v) {
                  widget.onFolderAdded(v);
                  setState(() => _addingFolder = false);
                },
                onCancel: () => setState(() => _addingFolder = false),
              ),

            // ─ タグ ─
            _SectionHeader(
                c: c,
                label: 'タグ',
                onAdd: () => setState(() => _addingTag = true)),

            ...widget.tags.map((t) {
              if (_editingTagId == t.id) {
                return _EditTile(
                  key: ValueKey(t.id),
                  c: c,
                  initialValue: t.name,
                  onConfirm: (v) {
                    widget.onTagRenamed(Tag(id: t.id, name: v));
                    setState(() => _editingTagId = null);
                  },
                  onCancel: () => setState(() => _editingTagId = null),
                );
              }
              final isActive = widget.activeTagId == t.id;
              return _NavTile(
                key: ValueKey(t.id),
                c: c,
                icon: Icons.label_outline,
                label: t.name,
                isActive: isActive,
                onTap: () => widget.onTagTap(t.id),
                onEdit: () => setState(() => _editingTagId = t.id),
              );
            }),

            if (_addingTag)
              _EditTile(
                key: const ValueKey('new_tag'),
                c: c,
                initialValue: '',
                onConfirm: (v) {
                  widget.onTagAdded(v);
                  setState(() => _addingTag = false);
                },
                onCancel: () => setState(() => _addingTag = false),
              ),
          ]),
        ),

        // ─ Bottom: ゴミ箱 + テーマ ─────────────────
        Divider(height: 1, color: c.border),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(children: [
            Expanded(
              child: InkWell(
                onTap: widget.onTrashTap,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: widget.showTrash ? c.active : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    Icon(Icons.delete_outline,
                        size: 15,
                        color: widget.showTrash ? c.accent : c.icon),
                    const SizedBox(width: 6),
                    Text('ゴミ箱',
                        style: GoogleFonts.notoSansJp(
                            fontSize: 12,
                            color: widget.showTrash ? c.activeText : c.subtext,
                            fontWeight: widget.showTrash
                                ? FontWeight.w600
                                : FontWeight.normal)),
                  ]),
                ),
              ),
            ),
            // テーマボタン (コーナーに配置)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTheme,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(7),
                  child: Icon(Icons.palette_outlined,
                      size: 17, color: c.icon),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── ナビゲーション用タイル ────────────────────────
class _NavTile extends StatelessWidget {
  final AppColors c;
  final IconData icon;
  final String label;
  final bool isActive;
  final bool draggable;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  const _NavTile({
    super.key,
    required this.c,
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.draggable = false,
    this.onEdit,
  });

  @override
  Widget build(BuildContext ctx) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: isActive ? c.active : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            if (draggable) ...[
              Icon(Icons.drag_indicator, size: 12, color: c.border),
              const SizedBox(width: 2),
            ],
            Icon(icon, size: 15, color: isActive ? c.accent : c.icon),
            const SizedBox(width: 7),
            Expanded(
                child: Text(label,
                    style: GoogleFonts.notoSansJp(
                      fontSize: 12,
                      color: isActive ? c.activeText : c.text,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis)),
            if (onEdit != null)
              GestureDetector(
                onTap: onEdit,
                child: Icon(Icons.edit_outlined, size: 12, color: c.subtext),
              ),
          ]),
        ),
      ),
    );
  }
}

// ── セクションヘッダー ────────────────────────
class _SectionHeader extends StatelessWidget {
  final AppColors c;
  final String label;
  final VoidCallback onAdd;
  const _SectionHeader(
      {required this.c, required this.label, required this.onAdd});
  @override
  Widget build(BuildContext ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 2),
        child: Row(children: [
          Text(label,
              style: GoogleFonts.notoSansJp(
                  fontSize: 10,
                  color: c.subtext,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0)),
          const Spacer(),
          GestureDetector(
            onTap: onAdd,
            child: Icon(Icons.add, size: 14, color: c.subtext),
          ),
        ]),
      );
}

// ── 編集タイル ────────────────────────
class _EditTile extends StatefulWidget {
  final AppColors c;
  final String initialValue;
  final Function(String) onConfirm;
  final VoidCallback onCancel;
  const _EditTile(
      {super.key,
      required this.c,
      required this.initialValue,
      required this.onConfirm,
      required this.onCancel});
  @override
  State<_EditTile> createState() => _EditTileState();
}

class _EditTileState extends State<_EditTile> {
  late final TextEditingController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext ctx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(children: [
          Expanded(
              child: TextField(
            controller: _ctrl,
            autofocus: true,
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) widget.onConfirm(v.trim());
            },
            style: GoogleFonts.notoSansJp(fontSize: 12, color: widget.c.text),
            decoration: InputDecoration(
              filled: true,
              fillColor: widget.c.input,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: BorderSide(color: widget.c.accent)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              isDense: true,
            ),
          )),
          IconButton(
              icon: Icon(Icons.check, size: 14, color: widget.c.accent),
              onPressed: () {
                if (_ctrl.text.trim().isNotEmpty) {
                  widget.onConfirm(_ctrl.text.trim());
                }
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints()),
          IconButton(
              icon: Icon(Icons.close, size: 14, color: widget.c.subtext),
              onPressed: widget.onCancel,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints()),
        ]),
      );
}

// ══════════════════════════════════════════
// Note List  (redesigned cards)
// ══════════════════════════════════════════
class _NoteList extends StatelessWidget {
  final AppColors colors;
  final List<Note> notes;
  final List<Tag> tags;
  final Note? selected;
  final SortMode sort;
  final String search;
  final int count;
  final bool showTrash;
  final Function(String) onSearchChanged;
  final Function(SortMode) onSortChanged;
  final Function(Note) onNoteTap;
  final VoidCallback onNewNote;
  final Function(String) onRestoreNote;
  final Function(String) onHardDeleteNote;
  final VoidCallback onEmptyTrash;
  final VoidCallback onExport;
  final VoidCallback onImport;
  final VoidCallback onImportUpNote;

  const _NoteList({
    required this.colors,
    required this.notes,
    required this.tags,
    required this.selected,
    required this.sort,
    required this.search,
    required this.count,
    required this.showTrash,
    required this.onSearchChanged,
    required this.onSortChanged,
    required this.onNoteTap,
    required this.onNewNote,
    required this.onRestoreNote,
    required this.onHardDeleteNote,
    required this.onEmptyTrash,
    required this.onExport,
    required this.onImport,
    required this.onImportUpNote,
  });

  AppColors get c => colors;

  String _tagName(String id) => tags
      .firstWhere((t) => t.id == id, orElse: () => const Tag(id: '', name: ''))
      .name;

  @override
  Widget build(BuildContext ctx) {
    return Expanded(
      child: Column(children: [
        // ─── Header bar (search + sort + menu) ───────────
        Container(
          height: 52,
          color: c.header,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(children: [
            // Search field (no extra gray bg wrapping, border only)
            Expanded(
              child: TextField(
                onChanged: onSearchChanged,
                style: GoogleFonts.notoSansJp(fontSize: 13, color: c.text),
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search, size: 17, color: c.icon),
                  hintText: '検索',
                  hintStyle: GoogleFonts.notoSansJp(
                      color: c.subtext, fontSize: 13),
                  filled: true,
                  fillColor: c.input,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: c.accent, width: 1.5),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Sort
            PopupMenuButton<SortMode>(
              initialValue: sort,
              onSelected: onSortChanged,
              tooltip: '並べ替え',
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                    color: c.input, borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.sort, size: 15, color: c.subtext),
                  const SizedBox(width: 3),
                  Text(_sortLabel(sort),
                      style: GoogleFonts.notoSansJp(
                          fontSize: 11, color: c.subtext)),
                ]),
              ),
              itemBuilder: (_) => SortMode.values
                  .map((s) => PopupMenuItem(
                      value: s,
                      child: Text(_sortLabel(s),
                          style: GoogleFonts.notoSansJp(
                              fontSize: 13, color: c.text))))
                  .toList(),
            ),
            const SizedBox(width: 2),
            // Settings menu
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 19, color: c.icon),
              tooltip: 'メニュー',
              onSelected: (v) {
                if (v == 'export') onExport();
                if (v == 'import') onImport();
                if (v == 'import_upnote') onImportUpNote();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: 'export',
                    child: Row(children: [
                      Icon(Icons.upload_outlined, size: 16, color: c.icon),
                      const SizedBox(width: 8),
                      Text('エクスポート',
                          style: GoogleFonts.notoSansJp(
                              fontSize: 13, color: c.text)),
                    ])),
                PopupMenuItem(
                    value: 'import',
                    child: Row(children: [
                      Icon(Icons.download_outlined, size: 16, color: c.icon),
                      const SizedBox(width: 8),
                      Text('インポート',
                          style: GoogleFonts.notoSansJp(
                              fontSize: 13, color: c.text)),
                    ])),
                PopupMenuItem(
                    value: 'import_upnote',
                    child: Row(children: [
                      Icon(Icons.folder_zip_outlined, size: 16, color: c.icon),
                      const SizedBox(width: 8),
                      Text('UpNoteインポート',
                          style: GoogleFonts.notoSansJp(
                              fontSize: 13, color: c.text)),
                    ])),
              ],
            ),
          ]),
        ),
        Divider(height: 1, color: c.border),

        // ─── Count + New ───────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Row(children: [
            Text('$count 件',
                style: GoogleFonts.notoSansJp(
                    fontSize: 11,
                    color: c.subtext,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            if (showTrash && count > 0)
              TextButton.icon(
                onPressed: onEmptyTrash,
                icon: const Icon(Icons.delete_forever,
                    size: 13, color: Colors.red),
                label: Text('すべて空にする',
                    style: GoogleFonts.notoSansJp(
                        fontSize: 11,
                        color: Colors.red,
                        fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                ),
              )
            else if (!showTrash)
              GestureDetector(
                onTap: onNewNote,
                child: Icon(Icons.add_circle_outline,
                    size: 19, color: c.accent),
              ),
          ]),
        ),

        // ─── Note Cards ───────────────────────────────
        Expanded(
            child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          itemCount: notes.length,
          itemBuilder: (_, i) {
            final n = notes[i];
            final isSelected = selected?.id == n.id;
            final preview = n.body.isEmpty
                ? ''
                : _extractBodyPreview(n.body);

            return GestureDetector(
              onTap: showTrash ? null : () => onNoteTap(n),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: isSelected ? c.accentSoft : c.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? c.accent : c.border,
                    width: isSelected ? 1.5 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    )
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(11),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    // ── Title row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            n.title.isEmpty ? '（タイトルなし）' : n.title,
                            style: GoogleFonts.notoSansJp(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color:
                                  isSelected ? c.activeText : c.text,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (n.isPinned) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.push_pin,
                              size: 12, color: c.accent),
                        ],
                      ],
                    ),

                    // ── Thumbnail + body preview
                    if (n.imagePaths.isNotEmpty || preview.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        if (preview.isNotEmpty)
                          Expanded(
                            child: Text(
                              preview,
                              style: GoogleFonts.notoSansJp(
                                  fontSize: 11,
                                  color: c.subtext,
                                  height: 1.5),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (n.imagePaths.isNotEmpty) ...[
                          if (preview.isNotEmpty) const SizedBox(width: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(7),
                            child: Image.file(
                              File(n.imagePaths.first),
                              width: 72,
                              height: 54,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 72,
                                height: 54,
                                decoration: BoxDecoration(
                                    color: c.input,
                                    borderRadius:
                                        BorderRadius.circular(7)),
                                child: Icon(Icons.image_outlined,
                                    size: 20, color: c.icon),
                              ),
                            ),
                          ),
                        ],
                      ]),
                    ],

                    const SizedBox(height: 7),

                    // ── Footer: date + tags + trash actions
                    Row(
                      children: [
                        // Date
                        Text(
                          _fmtDate(n.updatedAt),
                          style: GoogleFonts.notoSansJp(
                              fontSize: 10, color: c.subtext),
                        ),
                        // Tags
                        if (n.tagIds.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          ...n.tagIds.take(2).map((id) => Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: c.accentSoft,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '#${_tagName(id)}',
                                    style: GoogleFonts.notoSansJp(
                                        fontSize: 9,
                                        color: c.accent,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              )),
                        ],
                        const Spacer(),
                        // Trash actions
                        if (showTrash) ...[
                          _TrashBtn(
                            label: '復元',
                            color: c.accent,
                            bg: c.accentSoft,
                            onTap: () => onRestoreNote(n.id),
                          ),
                          const SizedBox(width: 5),
                          _TrashBtn(
                            label: '完全削除',
                            color: Colors.red,
                            bg: const Color(0xFFFFEEEE),
                            onTap: () => onHardDeleteNote(n.id),
                          ),
                        ],
                      ],
                    ),
                  ]),
                ),
              ),
            );
          },
        )),
      ]),
    );
  }

  String _fmtDate(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.month}/${dt.day}';
  }
}

class _TrashBtn extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;
  final VoidCallback onTap;
  const _TrashBtn(
      {required this.label,
      required this.color,
      required this.bg,
      required this.onTap});
  @override
  Widget build(BuildContext ctx) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
          child: Text(label,
              style: GoogleFonts.notoSansJp(
                  fontSize: 10, color: color, fontWeight: FontWeight.w600)),
        ),
      );
}
