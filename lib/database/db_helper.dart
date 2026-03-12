import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/note.dart';
import '../models/folder.dart';
import '../models/tag.dart';

class DbHelper {
  static final DbHelper _i = DbHelper._();
  factory DbHelper() => _i;
  DbHelper._();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _init();
    return _db!;
  }

  Future<Database> _init() async {
    final path = join(await getDatabasesPath(), 'evernote_personal.db');
    return openDatabase(path, version: 1, onCreate: (db, _) async {
      await db.execute('''
        CREATE TABLE folders(
          id TEXT PRIMARY KEY, name TEXT, sort_order INTEGER DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE tags(id TEXT PRIMARY KEY, name TEXT)
      ''');
      await db.execute('''
        CREATE TABLE notes(
          id TEXT PRIMARY KEY,
          title TEXT, body TEXT, folder_id TEXT,
          tag_ids TEXT, image_paths TEXT,
          created_at TEXT, updated_at TEXT,
          is_pinned INTEGER DEFAULT 0,
          is_deleted INTEGER DEFAULT 0
        )
      ''');
      // デフォルトフォルダ
      await db.insert('folders', {'id': 'f_work',    'name': '仕事',         'sort_order': 0});
      await db.insert('folders', {'id': 'f_private', 'name': 'プライベート', 'sort_order': 1});
      await db.insert('folders', {'id': 'f_invest',  'name': '投資',         'sort_order': 2});
      await db.insert('folders', {'id': 'f_novel',   'name': '小説',         'sort_order': 3});
      // デフォルトタグ
      await db.insert('tags', {'id': 't1', 'name': '重要'});
      await db.insert('tags', {'id': 't2', 'name': 'TODO'});
      await db.insert('tags', {'id': 't3', 'name': 'アイデア'});
      await db.insert('tags', {'id': 't4', 'name': '読み返す'});
    });
  }

  // ── Folders ────────────────────────────
  Future<List<Folder>> getFolders() async {
    final rows = await (await db).query('folders', orderBy: 'sort_order ASC');
    return rows.map(Folder.fromMap).toList();
  }

  Future<void> insertFolder(Folder f) async =>
      (await db).insert('folders', f.toMap());

  Future<void> updateFolder(Folder f) async =>
      (await db).update('folders', f.toMap(), where: 'id=?', whereArgs: [f.id]);

  Future<void> deleteFolder(String id) async =>
      (await db).delete('folders', where: 'id=?', whereArgs: [id]);

  Future<void> reorderFolders(List<Folder> folders) async {
    final batch = (await db).batch();
    for (var i = 0; i < folders.length; i++) {
      batch.update('folders', {'sort_order': i},
          where: 'id=?', whereArgs: [folders[i].id]);
    }
    await batch.commit(noResult: true);
  }

  // ── Tags ───────────────────────────────
  Future<List<Tag>> getTags() async {
    final rows = await (await db).query('tags');
    return rows.map(Tag.fromMap).toList();
  }

  Future<void> insertTag(Tag t) async =>
      (await db).insert('tags', t.toMap());

  Future<void> updateTag(Tag t) async =>
      (await db).update('tags', t.toMap(), where: 'id=?', whereArgs: [t.id]);

  Future<void> deleteTag(String id) async =>
      (await db).delete('tags', where: 'id=?', whereArgs: [id]);

  // ── Notes ──────────────────────────────
  Future<List<Note>> getNotes({bool includeDeleted = false}) async {
    final rows = await (await db).query(
      'notes',
      where: includeDeleted ? null : 'is_deleted=0',
      orderBy: 'is_pinned DESC, updated_at DESC',
    );
    return rows.map(Note.fromMap).toList();
  }

  Future<Note?> getNoteById(String id) async {
    final rows = await (await db).query('notes', where: 'id=?', whereArgs: [id]);
    return rows.isEmpty ? null : Note.fromMap(rows.first);
  }

  Future<void> insertNote(Note n) async =>
      (await db).insert('notes', n.toMap());

  Future<void> updateNote(Note n) async =>
      (await db).update('notes', n.toMap(), where: 'id=?', whereArgs: [n.id]);

  Future<void> softDeleteNote(String id) async =>
      (await db).update('notes', {'is_deleted': 1}, where: 'id=?', whereArgs: [id]);

  Future<void> restoreNote(String id) async =>
      (await db).update('notes', {'is_deleted': 0}, where: 'id=?', whereArgs: [id]);

  Future<void> hardDeleteNote(String id) async =>
      (await db).delete('notes', where: 'id=?', whereArgs: [id]);

  Future<List<Note>> searchNotes(String q) async {
    final rows = await (await db).query(
      'notes',
      where: "is_deleted=0 AND (title LIKE ? OR body LIKE ?)",
      whereArgs: ['%$q%', '%$q%'],
      orderBy: 'updated_at DESC',
    );
    return rows.map(Note.fromMap).toList();
  }

  // ── Export / Import ────────────────────
  Future<Map<String, dynamic>> exportAll() async {
    final folders = await getFolders();
    final tags    = await getTags();
    final notes   = await getNotes(includeDeleted: true);
    return {
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'folders': folders.map((f) => f.toMap()).toList(),
      'tags':    tags.map((t) => t.toMap()).toList(),
      'notes':   notes.map((n) => n.toMap()).toList(),
    };
  }

  Future<void> importAll(Map<String, dynamic> data) async {
    final d = await db;
    final batch = d.batch();
    for (var f in (data['folders'] as List)) {
      batch.insert('folders', Map<String, dynamic>.from(f),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    for (var t in (data['tags'] as List)) {
      batch.insert('tags', Map<String, dynamic>.from(t),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    for (var n in (data['notes'] as List)) {
      batch.insert('notes', Map<String, dynamic>.from(n),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }
}
