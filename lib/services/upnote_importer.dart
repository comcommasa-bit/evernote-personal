import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../database/db_helper.dart';
import '../models/note.dart';
import '../models/folder.dart';
import '../models/tag.dart';

class UpNoteImporter {
  final _db = DbHelper();
  final _uuid = const Uuid();

  /// ZIPファイルからUpNoteのノートをインポートする
  /// 戻り値: インポートしたノート数
  Future<int> importZip(String zipPath) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // 画像の保存先
    final docsDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${docsDir.path}/upnote_images');
    await imagesDir.create(recursive: true);

    // 画像ファイルを先に展開 (相対パス -> 保存先パス)
    final imageMap = <String, String>{};
    for (final file in archive) {
      if (!file.isFile) continue;
      final name = file.name.toLowerCase();
      if (name.endsWith('.jpg') ||
          name.endsWith('.jpeg') ||
          name.endsWith('.png') ||
          name.endsWith('.gif') ||
          name.endsWith('.webp')) {
        final safeName = file.name.replaceAll(RegExp(r'[/\\]'), '_');
        final outPath = '${imagesDir.path}/$safeName';
        await File(outPath).writeAsBytes(file.content as List<int>);
        imageMap[file.name] = outPath;
        // ファイル名だけでも引けるように登録
        final basename = file.name.split('/').last;
        imageMap[basename] ??= outPath;
      }
    }

    // 既存フォルダ・タグを取得
    final existingFolders = await _db.getFolders();
    final existingTags = await _db.getTags();
    final folderMap = {for (final f in existingFolders) f.name: f.id};
    final tagMap = {for (final t in existingTags) t.name: t.id};

    int count = 0;

    for (final file in archive) {
      if (!file.isFile) continue;
      if (!file.name.endsWith('.md')) continue;

      final content = utf8.decode(file.content as List<int>, allowMalformed: true);
      final parsed = _parseFrontmatter(content);

      final body = parsed['body'] as String? ?? '';
      // タイトル優先順: フロントマター > 本文の見出し > ファイル名
      final fmTitle = parsed['title'] as String?;
      final headingMatch = RegExp(r'^#{1,3}\s+(.+)', multiLine: true).firstMatch(body);
      final title = (fmTitle != null && fmTitle.isNotEmpty)
          ? fmTitle
          : headingMatch?.group(1)?.trim() ?? _titleFromPath(file.name);
      final notebook = parsed['notebook'] as String? ?? '';
      final tagNames = parsed['tags'] as List<String>? ?? [];
      final createdStr = parsed['created'] as String? ?? '';
      final updatedStr = parsed['updated'] as String? ?? '';

      // フォルダ解決（なければ作成）
      String folderId =
          existingFolders.isNotEmpty ? existingFolders.first.id : '';
      if (notebook.isNotEmpty) {
        if (folderMap.containsKey(notebook)) {
          folderId = folderMap[notebook]!;
        } else {
          final newId = _uuid.v4();
          await _db.insertFolder(
              Folder(id: newId, name: notebook, sortOrder: folderMap.length));
          folderMap[notebook] = newId;
          folderId = newId;
        }
      }

      // タグ解決（なければ作成）
      final tagIds = <String>[];
      for (final name in tagNames) {
        if (name.isEmpty) continue;
        if (tagMap.containsKey(name)) {
          tagIds.add(tagMap[name]!);
        } else {
          final newId = _uuid.v4();
          await _db.insertTag(Tag(id: newId, name: name));
          tagMap[name] = newId;
          tagIds.add(newId);
        }
      }

      // 本文中の画像パスを解決
      final imagePaths = <String>[];
      final imgRegex = RegExp(r'!\[.*?\]\((.+?)\)');
      for (final match in imgRegex.allMatches(body)) {
        final ref = match.group(1)!;
        final resolved = imageMap[ref] ??
            imageMap[ref.split('/').last];
        if (resolved != null && !imagePaths.contains(resolved)) {
          imagePaths.add(resolved);
        }
      }

      final now = DateTime.now();
      final note = Note(
        id: _uuid.v4(),
        title: title,
        body: body,
        folderId: folderId,
        tagIds: tagIds,
        imagePaths: imagePaths,
        createdAt: _parseDate(createdStr) ?? now,
        updatedAt: _parseDate(updatedStr) ?? now,
      );

      await _db.insertNote(note);
      count++;
    }

    return count;
  }

  // ──────────────────────────────────────────
  // private helpers
  // ──────────────────────────────────────────

  /// YAMLフロントマターを解析してマップに返す
  Map<String, dynamic> _parseFrontmatter(String content) {
    if (!content.startsWith('---')) return {'body': content};

    final end = content.indexOf('\n---', 3);
    if (end == -1) return {'body': content};

    final fm = content.substring(3, end).trim();
    final body = content.substring(end + 4).trim();

    final result = <String, dynamic>{'body': body};
    final tags = <String>[];
    bool inTags = false;

    for (final line in fm.split('\n')) {
      // タグのリスト行 (  - tagname)
      if (inTags && line.startsWith('  - ')) {
        tags.add(line.substring(4).trim().replaceAll('"', ''));
        continue;
      }
      inTags = false;

      final colon = line.indexOf(':');
      if (colon == -1) continue;

      final key = line.substring(0, colon).trim();
      final value = line.substring(colon + 1).trim().replaceAll('"', '');

      switch (key) {
        case 'title':
          result['title'] = value;
        case 'created':
          result['created'] = value;
        case 'updated':
          result['updated'] = value;
        case 'notebook':
          result['notebook'] = value;
        case 'tags':
          if (value.startsWith('[')) {
            // tags: [tag1, tag2]
            final inner = value
                .replaceAll('[', '')
                .replaceAll(']', '');
            tags.addAll(inner
                .split(',')
                .map((e) => e.trim().replaceAll('"', ''))
                .where((e) => e.isNotEmpty));
          } else if (value.isEmpty) {
            inTags = true;
          }
      }
    }

    if (tags.isNotEmpty) result['tags'] = tags;
    return result;
  }

  String _titleFromPath(String path) {
    final name = path.split('/').last;
    return name.endsWith('.md') ? name.substring(0, name.length - 3) : name;
  }

  DateTime? _parseDate(String s) {
    if (s.isEmpty) return null;
    try {
      // "2023-01-15 10:30:00" -> "2023-01-15T10:30:00"
      return DateTime.parse(s.replaceFirst(' ', 'T'));
    } catch (_) {
      return null;
    }
  }
}
