import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../database/db_helper.dart';

/// 全データ（ノート・フォルダ・タグ・画像）を1つのZIPにまとめる / ZIPから復元する
///
/// ZIPの中身:
///   data.json   … DbHelper.exportAll() と同じ形式（画像パスは ZIP 内の相対パス）
///   images/xxx  … 画像ファイル
class BackupService {
  final _db = DbHelper();
  final _uuid = const Uuid();

  static const _dataFile = 'data.json';
  static const _imgDir = 'images';
  static const _blocksPrefix = '[[BLOCKS]]';

  /// エクスポート用ZIPのバイト列を作る
  /// 戻り値: bytes, notes（ノート数）, images（画像枚数）
  Future<({Uint8List bytes, int notes, int images})> buildZip() async {
    final data = await _db.exportAll();
    final archive = Archive();

    // 端末上の絶対パス → ZIP内の相対パス
    final pathMap = <String, String>{};
    final usedNames = <String>{};

    String? toZipPath(String absPath) {
      if (pathMap.containsKey(absPath)) return pathMap[absPath];
      final file = File(absPath);
      if (!file.existsSync()) return null;
      var name = p.basename(absPath);
      var i = 1;
      while (usedNames.contains(name)) {
        name = '${i}_${p.basename(absPath)}';
        i++;
      }
      usedNames.add(name);
      final bytes = file.readAsBytesSync();
      final zipPath = '$_imgDir/$name';
      archive.addFile(ArchiveFile.noCompress(zipPath, bytes.length, bytes));
      pathMap[absPath] = zipPath;
      return zipPath;
    }

    final notes = (data['notes'] as List).cast<Map<String, dynamic>>();
    for (final n in notes) {
      _rewriteNote(n, toZipPath);
    }

    final json = const JsonEncoder.withIndent('  ').convert({
      ...data,
      'version': 2,
    });
    final jsonBytes = utf8.encode(json);
    archive.addFile(ArchiveFile(_dataFile, jsonBytes.length, jsonBytes));

    final zip = ZipEncoder().encode(archive);
    if (zip == null) throw Exception('ZIPの作成に失敗しました');
    return (
      bytes: Uint8List.fromList(zip),
      notes: notes.length,
      images: pathMap.length,
    );
  }

  /// エクスポートしたZIPを読み込んで復元する（同じIDのデータは上書き）
  /// 戻り値: notes（ノート数）, images（画像枚数）
  Future<({int notes, int images})> importZip(String zipPath) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final dataEntry = archive.findFile(_dataFile);
    if (dataEntry == null) {
      throw Exception('このアプリのバックアップZIPではありません（$_dataFile がありません）');
    }

    final dir = await getApplicationDocumentsDirectory();
    final imgDir = Directory(p.join(dir.path, 'images'));
    await imgDir.create(recursive: true);

    // ZIP内の相対パス → 端末上の新しい絶対パス
    final pathMap = <String, String>{};
    for (final file in archive) {
      if (!file.isFile) continue;
      final name = file.name.replaceAll(r'\', '/');
      if (!name.startsWith('$_imgDir/')) continue;
      // 既存画像を上書きしないよう UUID を付けて保存
      final dest =
          p.join(imgDir.path, '${_uuid.v4()}_${p.basename(name)}');
      await File(dest)
          .writeAsBytes(Uint8List.fromList(file.content as List<int>));
      pathMap[name] = dest;
    }

    final data = jsonDecode(utf8.decode(
            Uint8List.fromList(dataEntry.content as List<int>)))
        as Map<String, dynamic>;
    final notes = (data['notes'] as List).cast<Map<String, dynamic>>();
    for (final n in notes) {
      _rewriteNote(n, (path) => pathMap[path]);
    }
    await _db.importAll(data);
    return (notes: notes.length, images: pathMap.length);
  }

  /// ノート1件の画像パス（image_paths と本文ブロック内の imagePath）を置き換える
  /// convert が null を返したパスはそのまま残す
  void _rewriteNote(
      Map<String, dynamic> note, String? Function(String) convert) {
    final paths = (note['image_paths'] as String?) ?? '';
    if (paths.isNotEmpty) {
      note['image_paths'] =
          paths.split(',').map((s) => convert(s) ?? s).join(',');
    }

    final body = (note['body'] as String?) ?? '';
    if (!body.startsWith(_blocksPrefix)) return;
    try {
      final blocks = jsonDecode(body.substring(_blocksPrefix.length)) as List;
      for (final b in blocks) {
        if (b is Map && b['imagePath'] is String) {
          final src = b['imagePath'] as String;
          b['imagePath'] = convert(src) ?? src;
        }
      }
      note['body'] = '$_blocksPrefix${jsonEncode(blocks)}';
    } catch (_) {
      // 本文が壊れている場合はそのまま
    }
  }
}
