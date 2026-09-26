import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../database/db_helper.dart';
import '../models/folder.dart';

/// OneNote のノートブック / セクション（一覧表示用）
class OneNoteItem {
  final String id;
  final String name;
  const OneNoteItem(this.id, this.name);
}

/// Microsoft Graph 経由で OneNote のページを取り込む
///
/// 認証: Microsoft ID プラットフォーム（OAuth2 + PKCE、flutter_appauth）
/// アプリ登録: Entra「Evernote-personal」、リダイレクトURI は下記 [_redirectUrl]
class OneNoteService {
  static const _clientId = '4a6d228b-a518-4f92-8688-5da6dab2eced';
  static const _redirectUrl = 'com.hippo.evernotepersonal://auth';
  static const _scopes = ['Notes.ReadWrite', 'User.Read', 'offline_access'];
  static const _config = AuthorizationServiceConfiguration(
    authorizationEndpoint:
        'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
    tokenEndpoint: 'https://login.microsoftonline.com/common/oauth2/v2.0/token',
  );
  static const _graph = 'https://graph.microsoft.com/v1.0/me/onenote';
  static const _kRefreshToken = 'onenote_refresh_token';
  static const _blocksPrefix = '[[BLOCKS]]';

  final _appAuth = const FlutterAppAuth();
  final _storage = const FlutterSecureStorage();
  final _db = DbHelper();
  final _uuid = const Uuid();

  String? _accessToken;
  DateTime? _expiry;

  // ── 認証 ───────────────────────────────
  Future<bool> isSignedIn() async =>
      (await _storage.read(key: _kRefreshToken)) != null;

  Future<void> signIn() async {
    final r = await _appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        _clientId,
        _redirectUrl,
        serviceConfiguration: _config,
        scopes: _scopes,
        promptValues: ['select_account'],
      ),
    );
    await _saveToken(r.accessToken, r.refreshToken,
        r.accessTokenExpirationDateTime);
  }

  Future<void> signOut() async {
    _accessToken = null;
    _expiry = null;
    await _storage.delete(key: _kRefreshToken);
  }

  Future<void> _saveToken(
      String? access, String? refresh, DateTime? expiry) async {
    _accessToken = access;
    _expiry = expiry;
    if (refresh != null) {
      await _storage.write(key: _kRefreshToken, value: refresh);
    }
  }

  /// 有効なアクセストークンを返す（期限切れならリフレッシュ）
  Future<String> _token() async {
    final now = DateTime.now().add(const Duration(minutes: 2));
    if (_accessToken != null && _expiry != null && _expiry!.isAfter(now)) {
      return _accessToken!;
    }
    final refresh = await _storage.read(key: _kRefreshToken);
    if (refresh == null) throw Exception('サインインしていません');
    final r = await _appAuth.token(TokenRequest(
      _clientId,
      _redirectUrl,
      serviceConfiguration: _config,
      refreshToken: refresh,
      scopes: _scopes,
    ));
    await _saveToken(
        r.accessToken, r.refreshToken, r.accessTokenExpirationDateTime);
    if (_accessToken == null) throw Exception('トークンを取得できませんでした');
    return _accessToken!;
  }

  // ── Graph API ──────────────────────────
  Future<http.Response> _get(String url) async {
    final res = await http.get(Uri.parse(url),
        headers: {'Authorization': 'Bearer ${await _token()}'});
    if (res.statusCode != 200) {
      throw Exception('OneNote の取得に失敗しました (${res.statusCode})');
    }
    return res;
  }

  /// @odata.nextLink を辿って value を全件取得
  Future<List<Map<String, dynamic>>> _getAll(String url) async {
    final items = <Map<String, dynamic>>[];
    String? next = url;
    while (next != null) {
      final json =
          jsonDecode(utf8.decode((await _get(next)).bodyBytes)) as Map;
      items.addAll((json['value'] as List).cast<Map<String, dynamic>>());
      next = json['@odata.nextLink'] as String?;
    }
    return items;
  }

  Future<List<OneNoteItem>> notebooks() async =>
      (await _getAll('$_graph/notebooks?\$select=id,displayName'))
          .map((j) => OneNoteItem(j['id'] as String, j['displayName'] as String))
          .toList();

  Future<List<OneNoteItem>> sections(String notebookId) async =>
      (await _getAll(
              '$_graph/notebooks/$notebookId/sections?\$select=id,displayName'))
          .map((j) => OneNoteItem(j['id'] as String, j['displayName'] as String))
          .toList();

  // ── 取り込み ───────────────────────────
  /// セクション内の全ページをノートとして取り込む
  /// 同じページを再度取り込むと上書き（ノートID = onenote_ページID）
  /// 戻り値: notes（ノート数）, images（画像枚数）
  Future<({int notes, int images})> importSection(
    OneNoteItem section, {
    void Function(int done, int total)? onProgress,
  }) async {
    final pages = await _getAll('$_graph/sections/${section.id}/pages'
        '?\$select=id,title,createdDateTime,lastModifiedDateTime&\$top=100');

    final folderId = await _folderIdFor(section.name);
    final dir = await getApplicationDocumentsDirectory();
    final imgDir = Directory(p.join(dir.path, 'images'));
    await imgDir.create(recursive: true);

    var imageCount = 0;
    for (var i = 0; i < pages.length; i++) {
      onProgress?.call(i, pages.length);
      final page = pages[i];
      final html = utf8.decode(
          (await _get('$_graph/pages/${page['id']}/content')).bodyBytes);
      final parsed = await _htmlToBlocks(html, imgDir.path);
      imageCount += parsed.images.length;

      final now = DateTime.now().toIso8601String();
      await _db.importAll({
        'folders': [],
        'tags': [],
        'notes': [
          {
            'id': 'onenote_${page['id']}',
            'title': (page['title'] as String?) ?? '',
            'body': parsed.blocks.isEmpty
                ? ''
                : '$_blocksPrefix${jsonEncode(parsed.blocks)}',
            'folder_id': folderId,
            'tag_ids': '',
            'image_paths': parsed.images.join(','),
            'created_at': _toLocalIso(page['createdDateTime']) ?? now,
            'updated_at': _toLocalIso(page['lastModifiedDateTime']) ?? now,
            'is_pinned': 0,
            'is_deleted': 0,
          }
        ],
      });
    }
    onProgress?.call(pages.length, pages.length);
    return (notes: pages.length, images: imageCount);
  }

  String? _toLocalIso(dynamic v) {
    if (v is! String) return null;
    return DateTime.tryParse(v)?.toLocal().toIso8601String();
  }

  /// セクション名と同じ名前のフォルダを使う（無ければ作る）
  Future<String> _folderIdFor(String name) async {
    final folders = await _db.getFolders();
    for (final f in folders) {
      if (f.name == name) return f.id;
    }
    final id = _uuid.v4();
    await _db.insertFolder(Folder(id: id, name: name, sortOrder: folders.length));
    return id;
  }

  // ── HTML → ブロック変換 ─────────────────
  Future<({List<Map<String, dynamic>> blocks, List<String> images})>
      _htmlToBlocks(String html, String imgDir) async {
    final doc = html_parser.parse(html);
    final blocks = <Map<String, dynamic>>[];
    final images = <String>[];
    final textLines = <String>[];

    Map<String, dynamic> block(String type,
            {String text = '',
            String? imagePath,
            bool checked = false,
            int listNumber = 1}) =>
        {
          'id': _uuid.v4(),
          'type': type,
          'text': text,
          'imagePath': imagePath,
          'checked': checked,
          'listNumber': listNumber,
          'textSize': 'medium',
          'imgSize': 'medium',
        };

    void flushText() {
      // 前後の空行を落として1つのテキストブロックにまとめる
      while (textLines.isNotEmpty && textLines.first.trim().isEmpty) {
        textLines.removeAt(0);
      }
      while (textLines.isNotEmpty && textLines.last.trim().isEmpty) {
        textLines.removeLast();
      }
      if (textLines.isNotEmpty) {
        blocks.add(block('text', text: textLines.join('\n')));
      }
      textLines.clear();
    }

    Future<void> addImage(dom.Element img) async {
      final url = img.attributes['data-fullres-src'] ?? img.attributes['src'];
      if (url == null || url.isEmpty) return;
      try {
        final Uint8List bytes = url.startsWith('https://graph.microsoft.com')
            ? (await _get(url)).bodyBytes
            : (await http.get(Uri.parse(url))).bodyBytes;
        final type = img.attributes['data-fullres-src-type'] ??
            img.attributes['data-src-type'] ??
            '';
        final ext = type.contains('png')
            ? '.png'
            : type.contains('gif')
                ? '.gif'
                : '.jpg';
        final dest = p.join(imgDir, '${_uuid.v4()}$ext');
        await File(dest).writeAsBytes(bytes);
        flushText();
        blocks.add(block('image', imagePath: dest));
        images.add(dest);
      } catch (_) {
        textLines.add('[画像を取得できませんでした]');
      }
    }

    /// 要素内のテキスト（画像を除く）。<br> は改行にする
    String textOf(dom.Element e) {
      final buf = StringBuffer();
      void walk(dom.Node n) {
        if (n is dom.Text) {
          buf.write(n.text);
        } else if (n is dom.Element) {
          if (n.localName == 'br') {
            buf.write('\n');
          } else if (n.localName != 'img') {
            n.nodes.forEach(walk);
          }
        }
      }

      e.nodes.forEach(walk);
      return buf.toString().replaceAll(' ', ' ').trim();
    }

    Future<void> walk(dom.Node node) async {
      if (node is dom.Text) {
        final t = node.text.trim();
        if (t.isNotEmpty) textLines.add(t);
        return;
      }
      if (node is! dom.Element) return;
      final tag = node.localName;

      switch (tag) {
        case 'img':
          await addImage(node);
          return;
        case 'p':
        case 'h1':
        case 'h2':
        case 'h3':
        case 'h4':
        case 'h5':
        case 'h6':
          final dataTag = node.attributes['data-tag'] ?? '';
          final text = textOf(node);
          if (dataTag.contains('to-do')) {
            flushText();
            blocks.add(block('checkbox',
                text: text, checked: dataTag.contains('to-do:completed')));
          } else {
            textLines.add(text);
          }
          for (final img in node.querySelectorAll('img')) {
            await addImage(img);
          }
          return;
        case 'ol':
          flushText();
          var n = 1;
          for (final li in node.children.where((c) => c.localName == 'li')) {
            blocks.add(block('numberedList', text: textOf(li), listNumber: n++));
            for (final img in li.querySelectorAll('img')) {
              await addImage(img);
            }
          }
          return;
        case 'ul':
          for (final li in node.children.where((c) => c.localName == 'li')) {
            final dataTag = li.attributes['data-tag'] ?? '';
            if (dataTag.contains('to-do')) {
              flushText();
              blocks.add(block('checkbox',
                  text: textOf(li),
                  checked: dataTag.contains('to-do:completed')));
            } else {
              textLines.add('・${textOf(li)}');
            }
            for (final img in li.querySelectorAll('img')) {
              await addImage(img);
            }
          }
          return;
        case 'table':
          for (final tr in node.querySelectorAll('tr')) {
            textLines.add(tr.children.map(textOf).join(' | '));
          }
          for (final img in node.querySelectorAll('img')) {
            await addImage(img);
          }
          return;
        case 'br':
          textLines.add('');
          return;
        case 'script':
        case 'style':
        case 'head':
        case 'title':
        case 'object':
          return;
        default:
          for (final child in node.nodes.toList()) {
            await walk(child);
          }
      }
    }

    final body = doc.body;
    if (body != null) {
      for (final child in body.nodes.toList()) {
        await walk(child);
      }
    }
    flushText();
    return (blocks: blocks, images: images);
  }
}
