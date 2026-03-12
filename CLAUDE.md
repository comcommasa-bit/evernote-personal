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
- **その他**: uuid, image_picker, path_provider, shared_preferences, file_picker

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
    settings_screen.dart     # 設定（テーマ切替、パスワード変更、エクスポート/インポート）
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

## 開発ガイドライン

- 日本語UIを維持する
- `DbHelper` はシングルトンパターン。`factory DbHelper() => _i;`
- ノートの削除は必ずソフトデリート（`is_deleted` フラグ）を先に行う
- tag_ids, image_paths はカンマ区切り文字列としてDBに保存
- テーマカラーは `AppColors` の各プロパティを使い、ハードコードしない
- `WillPopScope` で編集画面離脱時に自動保存
- フォントは NotoSansJP を使用
- テーマ選択は `shared_preferences` で永続化済み（`app_theme` キー）
- パスワードは `flutter_secure_storage` に保存（`app_password` キー）

## 作業の進め方（重要）

**一気に全部やらない。1つずつテストして仕上げること。**

### 基本ルール

1. **1機能ずつ作業する** — 複数の変更を同時に進めない
2. **変更したら必ずビルド確認** — `flutter analyze` と `flutter build` を通す
3. **画面単位でテストする** — 実機/エミュレータで動作確認してから次へ
4. **フェーズ完了時に立ち止まる** — 全体を俯瞰し、壊れている箇所がないか確認
5. **コミットは細かく** — 1機能 = 1コミット。まとめてコミットしない

### 残作業フェーズ

#### Phase 1: ビルド基盤の整備
- [ ] `flutter pub get` で依存解決
- [ ] `assets/images/hippo.png` を実際のカバ画像に差し替え
- [ ] `assets/fonts/` に NotoSansJP フォントファイルを配置
- [ ] `flutter analyze` でエラー0にする
- [ ] エミュレータで起動確認
- **ここで立ち止まり → 全画面が表示されるか確認**

#### Phase 2: ロック画面の動作確認
- [ ] パスワード初回設定フロー
- [ ] パスワード認証フロー
- [ ] 生体認証フロー（実機のみ）
- [ ] バックグラウンド復帰で再ロックされるか
- **ここで立ち止まり → ロック画面が安定動作するか確認**

#### Phase 3: ホーム画面 + ノート一覧
- [ ] フォルダ一覧の表示・追加・リネーム・並び替え
- [ ] タグ一覧の表示・追加・リネーム
- [ ] ノート一覧の表示・検索・ソート切り替え
- [ ] ゴミ箱表示
- **ここで立ち止まり → サイドバーとリストが正常か確認**

#### Phase 4: ノートエディタ
- [ ] 新規ノート作成 → タイトル・本文入力
- [ ] フォルダ変更・タグ付与/除去
- [ ] ピン留め切り替え
- [ ] 画像添付・削除
- [ ] 自動保存（戻るボタンで保存されるか）
- [ ] ソフトデリート → ゴミ箱に移動
- **ここで立ち止まり → CRUD全操作が正常か確認**

#### Phase 5: 設定画面
- [ ] テーマ切り替え → 即時反映されるか
- [ ] テーマがアプリ再起動後も維持されるか
- [ ] パスワード変更 → 次回ロック解除で有効か
- [ ] JSONエクスポート → ファイルが生成されるか
- [ ] JSONインポート → データが復元されるか
- **ここで立ち止まり → 設定が全機能正常か確認**

#### Phase 6: 仕上げ
- [ ] 全画面のテーマ切り替えテスト（5テーマ全部）
- [ ] ダークモードでの表示崩れチェック
- [ ] home_screen.dart の末尾（ノートリストのアイテム描画）が意図通りか確認
  - ※ スマホClaude Codeセッションでコードが途中で切れた可能性あり
  - ※ ピンアイコン表示後の本文プレビュー・日付・タグバッジ部分を要確認
- [ ] `WillPopScope` は deprecated → `PopScope` への移行を検討
- [ ] 不要な `print` や TODO コメントの除去
- [ ] 最終ビルド確認

### 注意事項（引き継ぎメモ）

- **hippo.png はプレースホルダー** — 1x1透明PNGが入っている。実際の紫カバ画像に差し替え必須
- **NotoSansJP フォントファイル未配置** — `assets/fonts/` ディレクトリにttfを配置すること
- **home_screen.dart の末尾は推測補完** — 元コードがピンアイコン表示行で切れていたため、本文プレビュー・日付・タグバッジ表示を補完した。意図と異なる場合は修正すること
- **UpNoteインポート機能は未実装** — 要件にあったがまだ作成していない。Markdownパーサーの追加が必要
- **ツールバーのボタン（太字・斜体等）は未実装** — `onPressed: () {}` のまま。リッチテキスト対応は別途検討
