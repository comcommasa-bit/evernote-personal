# Evernote-personal

個人用ノートアプリ（Flutter / Dart）

## プロジェクト概要

Evernoteライクな個人用メモアプリ。紫のカバ（hippo）をマスコットとする。
ロック画面（パスワード＋生体認証）→ ホーム画面（サイドバー＋ノート一覧）→ ノートエディタの3画面構成。

## 技術スタック

- **フレームワーク**: Flutter (Dart, SDK >=3.0.0)
- **状態管理**: Provider (`ChangeNotifierProvider` + `ThemeNotifier`)
- **DB**: sqflite（ローカルSQLite）
- **認証**: local_auth（生体認証）、flutter_secure_storage（パスワード保存）
- **その他**: uuid, image_picker, path_provider

## ディレクトリ構成

```
lib/
  main.dart              # エントリポイント、RootPage（ロック制御）
  app_theme.dart         # AppThemeMode, AppColors, ThemeNotifier, GlassBackground（6テーマ対応）
  database/
    db_helper.dart       # DbHelper シングルトン（folders, tags, notes CRUD）
  models/
    note.dart            # Note モデル（copyWith, fromMap/toMap）
    folder.dart          # Folder モデル
    tag.dart             # Tag モデル
  screens/
    lock_screen.dart     # パスワード入力 + 指紋認証
    home_screen.dart     # サイドバー + ノート一覧（検索、ソート、フォルダ/タグ管理）
    note_editor_screen.dart  # ノート編集（タイトル、本文、タグ、画像、ピン留め）
assets/
  images/
    hippo.png            # アプリアイコン（紫カバ）
```

## データベース設計

- **folders**: id(PK), name, sort_order
- **tags**: id(PK), name
- **notes**: id(PK), title, body, folder_id, tag_ids(カンマ区切り), image_paths(カンマ区切り), created_at, updated_at, is_pinned, is_deleted

デフォルトフォルダ: 仕事, プライベート, 投資, 小説
デフォルトタグ: 重要, TODO, アイデア, 読み返す

## テーマシステム

6種類のテーマ（`AppThemeMode`）:
- **white**: デフォルト、緑アクセント
- **dark**: ダークモード、緑アクセント
- **purple**: 紫アクセント
- **blue**: 青アクセント
- **orange**: オレンジアクセント
- **glass**: ガラスモーフィズム。濃い紺〜紫〜青のグラデーション背景＋鮮やかな色の玉（ピンク/紫/シアン/オレンジ）の上に、白12〜25%の半透明パネル＋背景ぼかし（sidebar・ヘッダー・ノートカード、sigma 20）、白文字。背景は `main.dart` の `MaterialApp.builder` で `GlassBackground` を敷く。`bg` は透明。ダイアログ/メニューは `colorScheme.surface` を不透明の濃紺(0xFF2A2656)にして透けないようにしている。ステータスバーアイコンは白

`ThemeNotifier.setMode()` で切り替え。全画面で `ctx.watch<ThemeNotifier>().colors` を使用。

## 主な機能

- ロック画面: パスワード認証 + 生体認証、バックグラウンド復帰時に再ロック
- フォルダ管理: 追加・リネーム・ドラッグ並び替え
- タグ管理: 追加・リネーム・ノートへの付与/除去
- ノート: 作成・編集・ピン留め・ソフトデリート（ゴミ箱）
- 検索: タイトル + 本文の部分一致
- ソート: 更新日 / 作成日 / 名前 / タグ
- 画像添付: image_picker でギャラリーから選択、サムネイル表示
- エクスポート / インポート: JSON形式の全データバックアップ

## 開発ガイドライン

- 日本語UIを維持する
- `DbHelper` はシングルトンパターン。`factory DbHelper() => _i;`
- ノートの削除は必ずソフトデリート（`is_deleted` フラグ）を先に行う
- tag_ids, image_paths はカンマ区切り文字列としてDBに保存
- テーマカラーは `AppColors` の各プロパティを使い、ハードコードしない
- `WillPopScope` で編集画面離脱時に自動保存
- フォントは NotoSansJP を使用

## 変更履歴

- 2026-09-25 / AI(Claude): テーマに「ガラス」(`AppThemeMode.glass`) を追加。`AppColors` に `shadow` / `shadowBlur`（既定値は従来と同じ黒4%・blur4）を追加し、ノートカードの影に使用。変更ファイル: `lib/app_theme.dart`, `lib/main.dart`, `lib/screens/home_screen.dart`。この環境に Flutter SDK が無いためビルド未実施（ブランチ `claude/glass-morphism-mode-l49myu`）
- 2026-09-25 / AI(Claude): ガラスモード時のみノートカードに背景ぼかし（`BackdropFilter`, sigma 12）を追加。`AppColors` に `blur`（既定0=無効、glassのみ12）を追加。変更ファイル: `lib/app_theme.dart`, `lib/screens/home_screen.dart`（`_glassBlur` 関数）。ビルド未実施（Flutter SDK 無し）
- 2026-09-25 / AI(Claude): ガラスモードが実機で白っぽく見えガラス感が無かったため配色を全面変更。背景を濃いグラデーション＋鮮やかな色の玉に、パネルを白12〜25%の半透明＋白文字に、ぼかしを sigma 20 に強化し、サイドバーとヘッダーにもぼかしを追加。ダイアログ面を濃紺、glass時の brightness を dark、ステータスバーアイコンを白に。変更ファイル: `lib/app_theme.dart`, `lib/screens/home_screen.dart`。ビルド未実施（Flutter SDK 無し）。ブランチ `claude/awesome-noether-5thbwf`
