import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../app_theme.dart';
import '../database/db_helper.dart';
import '../models/note.dart';
import '../models/folder.dart';
import '../models/tag.dart';
import 'note_editor_screen.dart';
import 'settings_screen.dart';

const _uuid = Uuid();

enum SortMode { updated, created, name, tag }

String _sortLabel(SortMode s) {
  switch (s) {
    case SortMode.updated: return '更新日';
    case SortMode.created: return '作成日';
    case SortMode.name:    return '名前';
    case SortMode.tag:     return 'タグ';
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
  List<Tag>    _tags    = [];
  List<Note>   _notes   = [];

  String?  _activeFolderId;   // null = すべてのメモ
  String   _search  = '';
  SortMode _sort    = SortMode.updated;
  Note?    _selected;

  bool _showTrash = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final f = await _db.getFolders();
    final t = await _db.getTags();
    final n = await _db.getNotes(includeDeleted: _showTrash);
    if (!mounted) return;
    setState(() { _folders = f; _tags = t; _notes = n; });
  }

  List<Note> get _filtered {
    var list = _notes.where((n) {
      if (_showTrash) return n.isDeleted;
      if (n.isDeleted) return false;
      final folderOk = _activeFolderId == null || n.folderId == _activeFolderId;
      final searchOk = _search.isEmpty ||
          n.title.contains(_search) || n.body.contains(_search);
      return folderOk && searchOk;
    }).toList();

    list.sort((a, b) {
      if (a.isPinned != b.isPinned) return b.isPinned ? 1 : -1;
      switch (_sort) {
        case SortMode.name:    return a.title.compareTo(b.title);
        case SortMode.tag:     return (a.tagIds.firstOrNull ?? '').compareTo(b.tagIds.firstOrNull ?? '');
        case SortMode.created: return b.createdAt.compareTo(a.createdAt);
        case SortMode.updated: return b.updatedAt.compareTo(a.updatedAt);
      }
    });
    return list;
  }

  Future<void> _newNote() async {
    final now = DateTime.now();
    final note = Note(
      id: _uuid.v4(),
      folderId: _activeFolderId ?? (_folders.isNotEmpty ? _folders.first.id : ''),
      createdAt: now, updatedAt: now,
    );
    await _db.insertNote(note);
    await _load();
    if (!mounted) return;
    _openEditor(note);
  }

  void _openEditor(Note note) async {
    await Navigator.push(context,
      MaterialPageRoute(builder: (_) => NoteEditorScreen(
        note: note, folders: _folders, tags: _tags,
        onSaved: (_) => _load(),
      )),
    );
    _load();
  }

  // ── Build ───────────────────────────────
  @override
  Widget build(BuildContext ctx) {
    final c = ctx.watch<ThemeNotifier>().colors;
    return Scaffold(
      backgroundColor: c.bg,
      body: Row(children: [
        _Sidebar(
          colors: c, folders: _folders, tags: _tags,
          activeFolderId: _activeFolderId, showTrash: _showTrash,
          onFolderTap: (id) => setState(() { _activeFolderId = id; _showTrash = false; }),
          onTrashTap:  ()  => setState(() { _showTrash = true; _activeFolderId = null; }),
          onFoldersReordered: (f) async { _folders = f; await _db.reorderFolders(f); setState(() {}); },
          onFolderAdded: (name) async {
            await _db.insertFolder(Folder(id: _uuid.v4(), name: name, sortOrder: _folders.length));
            _load();
          },
          onFolderRenamed: (f) async { await _db.updateFolder(f); _load(); },
          onTagAdded: (name) async { await _db.insertTag(Tag(id: _uuid.v4(), name: name)); _load(); },
          onTagRenamed: (t) async { await _db.updateTag(t); _load(); },
        ),
        _NoteList(
          colors: c, notes: _filtered, tags: _tags,
          selected: _selected, sort: _sort,
          search: _search,
          onSearchChanged: (v) => setState(() => _search = v),
          onSortChanged:   (s) => setState(() => _sort = s),
          onNoteTap: (n) { setState(() => _selected = n); _openEditor(n); },
          onNewNote: _newNote,
          count: _filtered.length,
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════
// Sidebar
// ══════════════════════════════════════════
class _Sidebar extends StatefulWidget {
  final AppColors colors;
  final List<Folder> folders;
  final List<Tag> tags;
  final String? activeFolderId;
  final bool showTrash;
  final Function(String?) onFolderTap;
  final VoidCallback onTrashTap;
  final Function(List<Folder>) onFoldersReordered;
  final Function(String) onFolderAdded;
  final Function(Folder) onFolderRenamed;
  final Function(String) onTagAdded;
  final Function(Tag) onTagRenamed;

  const _Sidebar({
    required this.colors, required this.folders, required this.tags,
    required this.activeFolderId, required this.showTrash,
    required this.onFolderTap, required this.onTrashTap,
    required this.onFoldersReordered, required this.onFolderAdded,
    required this.onFolderRenamed, required this.onTagAdded,
    required this.onTagRenamed,
  });

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  String? _editingFolderId;
  String? _editingTagId;
  bool _addingFolder = false;
  bool _addingTag    = false;

  AppColors get c => widget.colors;

  @override
  Widget build(BuildContext ctx) {
    return Container(
      width: 200,
      color: c.sidebar,
      child: Column(children: [
        // Header
        Container(
          height: 52,
          decoration: BoxDecoration(
            color: c.header,
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            Image.asset('assets/images/hippo.png', width: 26, height: 26),
            const SizedBox(width: 8),
            Text('Evernote', style: TextStyle(
              fontWeight: FontWeight.w700, fontSize: 14, color: c.text)),
          ]),
        ),

        // New note button
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {}, // handled in parent
              icon: const Icon(Icons.add, size: 16),
              label: const Text('新規メモ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: c.accent, foregroundColor: c.accentText,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                elevation: 0,
              ),
            ),
          ),
        ),

        Expanded(child: ListView(padding: EdgeInsets.zero, children: [

          // すべてのメモ
          _FolderTile(
            c: c, label: 'すべてのメモ',
            isActive: widget.activeFolderId == null && !widget.showTrash,
            onTap: () => widget.onFolderTap(null),
          ),

          // ── フォルダ ──
          _SectionHeader(c: c, label: 'フォルダ',
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
                return _EditTile(key: ValueKey(f.id), c: c,
                  initialValue: f.name,
                  onConfirm: (v) {
                    widget.onFolderRenamed(Folder(id: f.id, name: v, sortOrder: f.sortOrder));
                    setState(() => _editingFolderId = null);
                  },
                  onCancel: () => setState(() => _editingFolderId = null),
                );
              }
              return _FolderTile(
                key: ValueKey(f.id), c: c, label: f.name,
                isActive: widget.activeFolderId == f.id,
                draggable: true,
                onTap: () => widget.onFolderTap(f.id),
                onEdit: () => setState(() => _editingFolderId = f.id),
              );
            }).toList(),
          ),

          if (_addingFolder) _EditTile(
            key: const ValueKey('new_folder'), c: c,
            initialValue: '',
            onConfirm: (v) { widget.onFolderAdded(v); setState(() => _addingFolder = false); },
            onCancel:  ()  => setState(() => _addingFolder = false),
          ),

          // ── タグ ──
          _SectionHeader(c: c, label: 'タグ',
            onAdd: () => setState(() => _addingTag = true)),

          ...widget.tags.map((t) {
            if (_editingTagId == t.id) {
              return _EditTile(key: ValueKey(t.id), c: c,
                initialValue: t.name,
                onConfirm: (v) {
                  widget.onTagRenamed(Tag(id: t.id, name: v));
                  setState(() => _editingTagId = null);
                },
                onCancel: () => setState(() => _editingTagId = null),
              );
            }
            return ListTile(
              key: ValueKey(t.id),
              dense: true, visualDensity: VisualDensity.compact,
              leading: Icon(Icons.label_outline, size: 14, color: c.icon),
              title: Text(t.name, style: TextStyle(fontSize: 12, color: c.subtext)),
              trailing: IconButton(
                icon: Icon(Icons.edit, size: 11, color: c.subtext),
                onPressed: () => setState(() => _editingTagId = t.id),
                padding: EdgeInsets.zero, constraints: const BoxConstraints(),
              ),
            );
          }),

          if (_addingTag) _EditTile(
            key: const ValueKey('new_tag'), c: c,
            initialValue: '',
            onConfirm: (v) { widget.onTagAdded(v); setState(() => _addingTag = false); },
            onCancel:  ()  => setState(() => _addingTag = false),
          ),
        ])),

        // ゴミ箱
        Divider(color: c.border, height: 1),
        ListTile(
          dense: true,
          leading: Icon(Icons.delete_outline, size: 16, color: c.icon),
          title: Text('ゴミ箱', style: TextStyle(fontSize: 13, color: c.subtext)),
          selected: widget.showTrash,
          onTap: widget.onTrashTap,
        ),
      ]),
    );
  }
}

// ── 小物ウィジェット ────────────────────────
class _SectionHeader extends StatelessWidget {
  final AppColors c; final String label; final VoidCallback onAdd;
  const _SectionHeader({required this.c, required this.label, required this.onAdd});
  @override
  Widget build(BuildContext ctx) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
    child: Row(children: [
      Text(label, style: TextStyle(fontSize: 10, color: c.subtext, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      const Spacer(),
      IconButton(icon: Icon(Icons.add, size: 14, color: c.subtext),
        onPressed: onAdd, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
    ]),
  );
}

class _FolderTile extends StatelessWidget {
  final AppColors c; final String label;
  final bool isActive; final bool draggable;
  final VoidCallback onTap; final VoidCallback? onEdit;
  const _FolderTile({super.key, required this.c, required this.label,
    required this.isActive, required this.onTap,
    this.draggable = false, this.onEdit});

  @override
  Widget build(BuildContext ctx) => ListTile(
    dense: true, visualDensity: VisualDensity.compact,
    tileColor: isActive ? c.active : null,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
    leading: draggable
        ? Icon(Icons.drag_indicator, size: 14, color: c.border)
        : const SizedBox(width: 14),
    title: Row(children: [
      Icon(Icons.folder_outlined, size: 14,
        color: isActive ? c.accent : c.icon),
      const SizedBox(width: 6),
      Expanded(child: Text(label, style: TextStyle(
        fontSize: 13, color: isActive ? c.activeText : c.text,
        fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
        overflow: TextOverflow.ellipsis,
      ))),
    ]),
    trailing: onEdit != null
        ? IconButton(icon: Icon(Icons.edit, size: 11, color: c.subtext),
            onPressed: onEdit, padding: EdgeInsets.zero, constraints: const BoxConstraints())
        : null,
    onTap: onTap,
  );
}

class _EditTile extends StatefulWidget {
  final AppColors c; final String initialValue;
  final Function(String) onConfirm; final VoidCallback onCancel;
  const _EditTile({super.key, required this.c, required this.initialValue,
    required this.onConfirm, required this.onCancel});
  @override State<_EditTile> createState() => _EditTileState();
}

class _EditTileState extends State<_EditTile> {
  late final TextEditingController _ctrl;
  @override void initState() { super.initState(); _ctrl = TextEditingController(text: widget.initialValue); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext ctx) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    child: Row(children: [
      Expanded(child: TextField(
        controller: _ctrl, autofocus: true,
        onSubmitted: (v) { if (v.trim().isNotEmpty) widget.onConfirm(v.trim()); },
        style: TextStyle(fontSize: 12, color: widget.c.text),
        decoration: InputDecoration(
          filled: true, fillColor: widget.c.input,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(7),
            borderSide: BorderSide(color: widget.c.accent)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          isDense: true,
        ),
      )),
      IconButton(icon: Icon(Icons.check, size: 14, color: widget.c.accent),
        onPressed: () { if (_ctrl.text.trim().isNotEmpty) widget.onConfirm(_ctrl.text.trim()); },
        padding: EdgeInsets.zero, constraints: const BoxConstraints()),
      IconButton(icon: Icon(Icons.close, size: 14, color: widget.c.subtext),
        onPressed: widget.onCancel,
        padding: EdgeInsets.zero, constraints: const BoxConstraints()),
    ]),
  );
}

// ══════════════════════════════════════════
// Note List
// ══════════════════════════════════════════
class _NoteList extends StatelessWidget {
  final AppColors colors;
  final List<Note> notes;
  final List<Tag> tags;
  final Note? selected;
  final SortMode sort;
  final String search;
  final int count;
  final Function(String) onSearchChanged;
  final Function(SortMode) onSortChanged;
  final Function(Note) onNoteTap;
  final VoidCallback onNewNote;

  const _NoteList({
    required this.colors, required this.notes, required this.tags,
    required this.selected, required this.sort, required this.search,
    required this.count, required this.onSearchChanged,
    required this.onSortChanged, required this.onNoteTap,
    required this.onNewNote,
  });

  AppColors get c => colors;

  String _tagName(String id) =>
      tags.firstWhere((t) => t.id == id, orElse: () => Tag(id: '', name: '')).name;

  @override
  Widget build(BuildContext ctx) {
    return Expanded(
      child: Column(children: [
        // Header bar
        Container(
          height: 52,
          color: c.header,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Expanded(child: Container(
              decoration: BoxDecoration(
                color: c.input, borderRadius: BorderRadius.circular(9)),
              child: TextField(
                onChanged: onSearchChanged,
                style: TextStyle(fontSize: 12, color: c.text),
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search, size: 15, color: c.icon),
                  hintText: '検索', hintStyle: TextStyle(color: c.subtext, fontSize: 12),
                  border: InputBorder.none, isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            )),
            const SizedBox(width: 8),
            // Sort
            PopupMenuButton<SortMode>(
              initialValue: sort,
              onSelected: onSortChanged,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: c.input, borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.swap_vert, size: 14, color: c.subtext),
                  const SizedBox(width: 4),
                  Text(_sortLabel(sort),
                    style: TextStyle(fontSize: 11, color: c.subtext)),
                ]),
              ),
              itemBuilder: (_) => SortMode.values.map((s) =>
                PopupMenuItem(value: s, child: Text(_sortLabel(s),
                  style: TextStyle(fontSize: 13, color: c.text)))).toList(),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(Icons.settings_outlined, size: 18, color: c.subtext),
              onPressed: () => Navigator.push(ctx,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ]),
        ),
        Divider(height: 1, color: c.border),

        // Count + new
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            Text('$count 件', style: TextStyle(fontSize: 11, color: c.subtext, fontWeight: FontWeight.w600)),
            const Spacer(),
            IconButton(icon: Icon(Icons.add_circle_outline, size: 18, color: c.accent),
              onPressed: onNewNote, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
          ]),
        ),

        // List
        Expanded(child: ListView.builder(
          itemCount: notes.length,
          itemBuilder: (_, i) {
            final n = notes[i];
            final isSelected = selected?.id == n.id;
            return GestureDetector(
              onTap: () => onNoteTap(n),
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? c.accentSoft : Colors.transparent,
                  border: Border(left: BorderSide(
                    color: isSelected ? c.accent : Colors.transparent, width: 3)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // サムネイル
                  if (n.imagePaths.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.asset(n.imagePaths.first,
                        width: 50, height: 38, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 50, height: 38,
                          decoration: BoxDecoration(
                            color: c.input, borderRadius: BorderRadius.circular(6)),
                          child: Icon(Icons.image_outlined, size: 18, color: c.icon),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(n.title.isEmpty ? '（タイトルなし）' : n.title,
                        style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600,
                          color: isSelected ? c.activeText : c.text),
                        overflow: TextOverflow.ellipsis)),
                      if (n.isPinned) Icon(Icons.push_pin, size: 11, color: c.accent),
                    ]),
                    const SizedBox(height: 3),
                    Text(
                      n.body.isEmpty ? '（本文なし）' : n.body,
                      style: TextStyle(fontSize: 11, color: c.subtext),
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(children: [
                      Text(
                        '${n.updatedAt.month}/${n.updatedAt.day}',
                        style: TextStyle(fontSize: 10, color: c.subtext),
                      ),
                      if (n.tagIds.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        ...n.tagIds.take(2).map((id) => Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: c.accentSoft,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('#${_tagName(id)}',
                              style: TextStyle(fontSize: 9, color: c.accent)),
                          ),
                        )),
                      ],
                    ]),
                  ])),
                ]),
              ),
            );
          },
        )),
      ]),
    );
  }
}
