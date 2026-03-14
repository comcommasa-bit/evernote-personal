import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../database/db_helper.dart';
import '../models/note.dart';
import '../models/folder.dart';
import '../models/tag.dart';

class UpNoteImporter {
  final _db = DbHelper();
  final _uuid = const Uuid();

  static const _imageExts = {'.jpg', '.jpeg', '.png', '.webp', '.heic'};

  /// ZIPファイルからUpNoteのノートをインポートする
  /// 戻り値: {'notes': インポートしたノート数, 'images': コピーした画像数}
  Future<Map<String, int>> importZip(String zipPath) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final dir = await getApplicationDocumentsDirectory();
    final imgDir = Directory(p.join(dir.path, 'images'));
    await imgDir.create(recursive: true);

    // 既存フォルダ・タグを取得
    final existingFolders = await _db.getFolders();
    final existingTags = await _db.getTags();
    final folderMap = {for (final f in existingFolders) f.name: f.id};
    final tagMap = {for (final t in existingTags) t.name: t.id};

    // 1回のループで画像と.mdを振り分け
    // imagePathMap: key=ZIPエントリ名(正規化済み), value=ローカルパス
    final imagePathMap = <String, String>{};
    final mdFiles = <ArchiveFile>[];
    int imageCount = 0;

    for (final file in archive) {
      if (!file.isFile) continue;
      final normalizedName = file.name.replaceAll(r'\', '/');
      final ext = p.extension(normalizedName).toLowerCase();

      if (_imageExts.contains(ext)) {
        // UUID付きファイル名で保存して衝突を防ぐ
        final uniqueName = '${_uuid.v4()}$ext';
        final dest = p.join(imgDir.path, uniqueName);
        await File(dest)
            .writeAsBytes(Uint8List.fromList(file.content as List<int>));
        // ZIPエントリ名（正規化）とファイル名だけの両方でひける
        imagePathMap[normalizedName] = dest;
        imagePathMap[p.basename(normalizedName)] = dest;
        imageCount++;
      } else if (normalizedName.endsWith('.md')) {
        mdFiles.add(file);
      }
    }

    int noteCount = 0;

    for (final file in mdFiles) {
      final content = utf8.decode(Uint8List.fromList(file.content as List<int>),
          allowMalformed: true);
      final normalizedName = file.name.replaceAll(r'\', '/');
      final parsed = _parseContent(content, normalizedName, imagePathMap);

      final title = parsed['title'] as String;
      final body = parsed['body'] as String;
      final notebook = parsed['notebook'] as String? ?? '';
      final tagNames = parsed['tags'] as List<String>? ?? [];
      final createdStr = parsed['created'] as String? ?? '';
      final updatedStr = parsed['updated'] as String? ?? '';
      final noteImagePaths = parsed['imagePaths'] as List<String>? ?? [];

      // フォルダ解決
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

      // タグ解決
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

      final now = DateTime.now();
      final note = Note(
        id: _uuid.v4(),
        title: title,
        body: body,
        folderId: folderId,
        tagIds: tagIds,
        imagePaths: noteImagePaths,
        createdAt: _parseDate(createdStr) ?? now,
        updatedAt: _parseDate(updatedStr) ?? now,
      );

      await _db.insertNote(note);
      noteCount++;
    }

    return {'notes': noteCount, 'images': imageCount};
  }

  // ──────────────────────────────────────────
  // private helpers
  // ──────────────────────────────────────────

  Map<String, dynamic> _parseContent(
      String content, String filePath, Map<String, String> imagePathMap) {
    String workingContent = content;
    String title = '';
    String notebook = '';
    final tags = <String>[];
    String created = '';
    String updated = '';

    // ステップ1: YAMLフロントマター
    if (content.startsWith('---')) {
      final end = content.indexOf('\n---', 3);
      if (end != -1) {
        final fm = content.substring(3, end).trim();
        workingContent = content.substring(end + 4);
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
            case 'title':
              if (value.isNotEmpty) title = value;
            case 'created':
              created = value;
            case 'updated':
              updated = value;
            case 'notebook':
              if (value.isNotEmpty) notebook = value;
            case 'tags':
              if (value.startsWith('[')) {
                tags.addAll(value
                    .replaceAll('[', '')
                    .replaceAll(']', '')
                    .split(',')
                    .map((e) => e.trim().replaceAll('"', ''))
                    .where((e) => e.isNotEmpty));
              } else if (value.isEmpty) {
                inTags = true;
              }
          }
        }
      }
    }

    // ステップ2: コメント形式
    final lines = workingContent.split('\n');
    final bodyLines = <String>[];

    for (final line in lines) {
      if ((line.startsWith('## ') || line.startsWith('# ')) && title.isEmpty) {
        title = line.replaceFirst(RegExp(r'^#{1,2}\s+'), '').trim();
      } else if (line.contains('<!-- category:') && notebook.isEmpty) {
        notebook = RegExp(r'<!--\s*category:\s*(.+?)\s*-->')
                .firstMatch(line)
                ?.group(1) ??
            '';
      } else if (line.contains('<!-- tags:') && tags.isEmpty) {
        final t =
            RegExp(r'<!--\s*tags:\s*(.+?)\s*-->').firstMatch(line)?.group(1) ??
                '';
        tags.addAll(
            t.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty));
      } else if (line.contains('<!-- created:') && created.isEmpty) {
        created = RegExp(r'<!--\s*created:\s*(.+?)\s*-->')
                .firstMatch(line)
                ?.group(1) ??
            '';
      } else if (line.contains('<!-- updated:') && updated.isEmpty) {
        updated = RegExp(r'<!--\s*updated:\s*(.+?)\s*-->')
                .firstMatch(line)
                ?.group(1) ??
            '';
      } else {
        bodyLines.add(line);
      }
    }

    // ステップ3: 画像パスを解決（バックスラッシュ対応）
    final noteImagePaths = <String>[];
    final bodyText = bodyLines.join('\n');
    final resolvedBody = bodyText.replaceAllMapped(
      RegExp(r'!\[.*?\]\((.*?)\)'),
      (m) {
        final raw = m.group(1) ?? '';
        final ref = raw.replaceAll(r'\', '/');
        final localPath = imagePathMap[ref] ?? imagePathMap[p.basename(ref)];
        if (localPath != null) {
          if (!noteImagePaths.contains(localPath)) {
            noteImagePaths.add(localPath);
          }
          return '![]($localPath)';
        }
        return '[画像]';
      },
    ).trim();

    return {
      'title': title.isNotEmpty ? title : _titleFromPath(filePath),
      'body': resolvedBody,
      'notebook': notebook,
      'tags': tags,
      'created': created,
      'updated': updated,
      'imagePaths': noteImagePaths,
    };
  }

  String _titleFromPath(String path) {
    final name = path.split('/').last;
    return name.endsWith('.md') ? name.substring(0, name.length - 3) : name;
  }

  DateTime? _parseDate(String s) {
    if (s.isEmpty) return null;
    try {
      return DateTime.parse(s.replaceFirst(' ', 'T'));
    } catch (_) {
      return null;
    }
  }
}
