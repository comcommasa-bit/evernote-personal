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
- **glass**: ガラスモーフィズム。半透明パネル＋白ハイライト枠＋浮遊シャドウ、インディゴアクセント。背景は `main.dart` の `MaterialApp.builder` で `GlassBackground`（パステルグラデーション＋色の玉）を敷く。`bg` は透明。ダイアログ/メニューは `colorScheme.surface` を不透明にして透けないようにしている

`ThemeNotifier.setMode()` で切り替え。全画面で `ctx.watch<ThemeNotifier>().colors` を使用。

## 主な機能

- ロック画面: パスワード認証 + 生体認証、バックグラウンド復帰時に再ロック
- フォルダ管理: 追加・リネーム・ドラッグ並び替え
- タグ管理: 追加・リネーム・ノートへの付与/除去
- ノート: 作成・編集・ピン留め・ソフトデリート（ゴミ箱）
- 検索: タイトル + 本文の部分一致
- ソート: 更新日 / 作成日 / 名前 / タグ
- 画像添付: image_picker でギャラリーから選択、サムネイル表示
- エクスポート / インポート: ZIP形式（`data.json` + `images/`）の全データバックアップ。保存先は保存ダイアログで選択。旧JSON形式のインポートも可（`lib/services/backup_service.dart`）

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
- 2026-09-25 / AI(Claude): デザイナー指定によりガラスモードを強化。`AppThemeMode.glass` の値を変更（sidebar 0x33FFFFFF, card 0x2EFFFFFF, header 0x33FFFFFF, subtext/icon 0xFF45496E, accentSoft 0x59E8E9FF, border 0x99FFFFFF, active 0x4DFFFFFF, activeText 0xFF3730A3, input 0x40FFFFFF。shadow/shadowBlur/blur は据え置き）。`GlassBackground` のグラデーションを [0xFFC9CFF7, 0xFFDCC8F4, 0xFFBFE6E2] に、色の玉4つを濃い色（紫/ティール/ピンク/青）に変更。`_glassBlur` に `radius` 引数を追加し、サイドバーとヘッダーバーにも適用。ノート編集画面とボトムシートも `c.card` を使うため透ける（実機未確認）。変更ファイル: `lib/app_theme.dart`, `lib/screens/home_screen.dart`
- 2026-09-25 / AI(Claude): 【確認した事実】Build 43 の APK は旧端末で「アプリはインストールされていません」となり上書き不可（Play プロテクトの警告の後）。別端末には新規インストールできた。`build.gradle.kts` の release は debug 署名、`pubspec.yaml` は `1.1.0+2` 固定。原因は署名鍵の不一致と推定（APK の署名は未比較）
- 2026-09-25 / AI(Claude): 上記デザイナー指定の変更を PR #6 で main にマージ。Build APK（run 44）成功、Release `build-44` に `Evernote-personal-v44.apk` を確認。実機での見た目は未確認
- 2026-09-26 / AI(Claude): 署名鍵の固定。`android/app/build.gradle.kts` に release 用 signingConfig を追加（`android/key.properties` があれば固定鍵、無ければ debug 鍵）。`.github/workflows/build-apk.yml` に GitHub Secrets `KEYSTORE_BASE64` / `KEYSTORE_PASSWORD` から `android/app/release.jks` と `android/key.properties` を生成する手順を追加（未設定ならビルド失敗）。versionCode は `--build-number=${{ github.run_number }}` で毎回増える。鍵: alias `evernote`、JKS、SHA-256 `3C:CB:A5:51:A8:4D:1E:3A:49:FC:37:8A:F8:A8:6F:36:93:C1:C6:AB:F4:90:FC:14:4B:9B:47:DA:26:42:92:D0`。鍵ファイルはリポジトリに入れない（`android/.gitignore` で除外済み）。ビルド未実施（Secrets 登録待ち）
- 2026-09-26 / AI(Claude): 【エラー記録】PR #7 マージ後の Build APK（run 45）が失敗。ログ上 `KEYSTORE_BASE64` / `KEYSTORE_PASSWORD` が空で「Secrets 未設定」エラーにより停止（Flutter ビルドまで到達せず）。Secrets の登録場所・名前の確認待ち
- 2026-09-26 / AI(Claude): Secrets 登録後、Build APK（run 46, workflow_dispatch, main）成功。Release `build-46` に `Evernote-personal-v46.apk` を確認。以降は固定鍵で署名される（APK の署名は未検証、実機インストール未確認）
- 2026-09-26 / AI(Claude): 写真も含むエクスポート/インポート。新規 `lib/services/backup_service.dart`（ZIP作成・復元、画像パスを ZIP 内相対パス⇔端末パスに書き換え。`image_paths` と本文ブロックの `imagePath` 両方）。`lib/screens/home_screen.dart` の `_exportData` を ZIP＋`FilePicker.saveFile`（保存先をユーザーが選択）に、`_importData` を ZIP/JSON 両対応に変更、未使用になった `path_provider` の import を削除。Flutter 3.41.4 SDK をこの環境に取得し `flutter analyze` 実施: エラー0、info 24件（変更前と同数）。APK ビルド・実機動作は未確認
- 2026-09-26 / AI(Claude): PR #8 マージ後の Build APK（run 47）成功。Release `build-47` に `Evernote-personal-v47.apk` を確認。Build 46 からの上書き更新・エクスポート/インポートの実機動作は未確認
- 2026-09-26 / AI(Claude): ユーザー報告「できたようにおもう」（Build 47 の上書き更新・エクスポート/インポート。項目ごとの結果は未取得）
