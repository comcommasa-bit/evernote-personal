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
      final parsed = _parseContent(content, file.name);

      final title = parsed['title'] as String;
      final body = parsed['body'] as String;
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

  /// UpNote Markdownをパースして title/body/notebook/tags/created/updated を返す
  /// ステップ1: YAMLフロントマター抽出（あれば）
  /// ステップ2: 残りをコメント形式でパース（## タイトル / <!-- category: --> など）
  Map<String, dynamic> _parseContent(String content, String filePath) {
    String workingContent = content;
    String title = '';
    String notebook = '';
    final tags = <String>[];
    String created = '';
    String updated = '';

    // ステップ1: YAMLフロントマター (---) を抽出
    if (content.startsWith('---')) {
      final end = content.indexOf('\n---', 3);
      if (end != -1) {
        final fm = content.substring(3, end).trim();
        workingContent = content.substring(end + 4); // 残りの本文
        bool inTags = false;
        for (final line in fm.split('\n')) {
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
            case 'title': if (value.isNotEmpty) title = value;
            case 'created': created = value;
            case 'updated': updated = value;
            case 'notebook': if (value.isNotEmpty) notebook = value;
            case 'tags':
              if (value.startsWith('[')) {
                tags.addAll(value.replaceAll('[', '').replaceAll(']', '')
                    .split(',').map((e) => e.trim().replaceAll('"', '')).where((e) => e.isNotEmpty));
              } else if (value.isEmpty) {
                inTags = true;
              }
          }
        }
      }
    }

    // ステップ2: コメント形式をパース（## タイトル / <!-- category: --> など）
    final lines = workingContent.split('\n');
    final bodyLines = <String>[];

    for (final line in lines) {
      if ((line.startsWith('## ') || line.startsWith('# ')) && title.isEmpty) {
        title = line.replaceFirst(RegExp(r'^#{1,2}\s+'), '').trim();
      } else if (line.contains('<!-- category:') && notebook.isEmpty) {
        notebook = RegExp(r'<!--\s*category:\s*(.+?)\s*-->').firstMatch(line)?.group(1) ?? '';
      } else if (line.contains('<!-- tags:') && tags.isEmpty) {
        final t = RegExp(r'<!--\s*tags:\s*(.+?)\s*-->').firstMatch(line)?.group(1) ?? '';
        tags.addAll(t.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty));
      } else if (line.contains('<!-- created:') && created.isEmpty) {
        created = RegExp(r'<!--\s*created:\s*(.+?)\s*-->').firstMatch(line)?.group(1) ?? '';
      } else if (line.contains('<!-- updated:') && updated.isEmpty) {
        updated = RegExp(r'<!--\s*updated:\s*(.+?)\s*-->').firstMatch(line)?.group(1) ?? '';
      } else {
        bodyLines.add(line);
      }
    }

    return {
      'title': title.isNotEmpty ? title : _titleFromPath(filePath),
      'body': bodyLines.join('\n').replaceAll(RegExp(r'!\[.*?\]\(.*?\)'), '[画像]').trim(),
      'notebook': notebook,
      'tags': tags,
      'created': created,
      'updated': updated,
    };
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
