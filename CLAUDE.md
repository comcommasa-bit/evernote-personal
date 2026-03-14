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
  app_theme.dart         # AppThemeMode, AppColors, ThemeNotifier（5テーマ対応）
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

5種類のテーマ（`AppThemeMode`）:
- **white**: デフォルト、緑アクセント
- **dark**: ダークモード、緑アクセント
- **purple**: 紫アクセント
- **blue**: 青アクセント
- **orange**: オレンジアクセント

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

## バージョン履歴

- **v26 (2026-03-14)**: 全機能追加
  - 指紋認証登録フロー（初回セットアップ: PW設定→生体認証案内の2ステップ）
  - `AuthService` 分離 (`lib/services/auth_service.dart`)
  - `SetupScreen` 新規作成 (`lib/screens/setup_screen.dart`)
  - ロック制御改善: バックグラウンド5分以内なら再ロックなし（`_lockGraceMinutes = 5`）
  - 新規ノート空保存防止: タイトル・本文・画像が全て空なら閉じた時に削除
  - ゴミ箱「すべて空にする」ボタン追加（ゴミ箱表示時に件数>0で表示）
  - 30日経過ゴミ箱ノートを起動時に自動削除（`deleteExpiredNotes()`）
  - エクスポート/インポート/UpNoteインポートにチュートリアルポップアップ追加

- **v27 (2026-03-14)**: エディター全面強化・認証改善
  - 指紋認証: `stickyAuth: true`・`PlatformException` エラーハンドリング強化、登録済み生体情報チェック追加
  - ノートエディター全面刷新（ブロック方式）:
    - テキストサイズ 小(12px)/中(16px)/大(22px) のブロック追加ツールバー
    - チェックボックス: Enter で自動的に次のチェック項目追加、空なら通常テキストへ切替
    - 連番リスト: Enter で次の連番自動追加、空なら通常テキストへ切替、番号の自動繰り上げ
    - 画像: `ImgSize` enum で小/中/大サイズ切替ボタン（現在サイズをハイライト表示）、画像ブロック削除ボタン
    - ノート一覧のbodyプレビューをブロック形式から可読テキストへ変換（`_extractBodyPreview`）
  - ノート一覧サムネイル拡大: 50×38 → 72×56px

## 開発ガイドライン

- 日本語UIを維持する
- `DbHelper` はシングルトンパターン。`factory DbHelper() => _i;`
- ノートの削除は必ずソフトデリート（`is_deleted` フラグ）を先に行う
- tag_ids, image_paths はカンマ区切り文字列としてDBに保存
- テーマカラーは `AppColors` の各プロパティを使い、ハードコードしない
- `WillPopScope` で編集画面離脱時に自動保存
- フォントは NotoSansJP を使用
