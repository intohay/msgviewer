# MsgViewer

チャットメッセージのZIPファイルをインポートして表示するFlutterアプリケーション

## 概要

MsgViewerは、CSVメッセージデータと関連メディアファイル（画像、動画、音声）を含むZIPアーカイブをインポートし、美しいチャットインターフェースで表示するアプリです。SQLiteデータベースを使用してメッセージを効率的に管理し、遅延読み込みによるパフォーマンス最適化を実現しています。

## 主な機能

- **ZIPインポート機能**: CSV形式のメッセージデータと関連メディアファイルを含むZIPファイルの処理
- **メッセージ表示**: テキストメッセージとインライン画像、動画、音声の表示
- **データベース管理**: SQLite（sqflite）によるメッセージメタデータとファイルパスの保存
- **効率的な読み込み**: ページネーション付き遅延読み込み（初期20件、スクロールで10件ずつ追加）
- **メディア対応**:
  - 画像/動画の自動サムネイル生成
  - ズーム対応フォトビューア
  - コントロール付きビデオプレーヤー
  - オーディオプレーヤー機能
- **カレンダーナビゲーション**: 特定の日付への会話ジャンプ
- **検索機能**: 会話内のフルテキスト検索
- **お気に入り**: メッセージのお気に入り登録と表示
- **カスタムアイコン**: トークごとのアイコンカスタマイズ

## 技術スタック

- **フレームワーク**: Flutter (Dart)
- **Flutter SDK**: >=3.3.4 <4.0.0
- **プラットフォーム**: クロスプラットフォーム（iOS、Android）
- **データベース**: SQLite（sqfliteパッケージ使用）
- **状態管理**: StatefulWidget（従来のFlutterアプローチ）

## プロジェクト構造

```
msgviewer/
├── lib/
│   ├── main.dart              # アプリエントリーポイント、初期化
│   ├── home_page.dart         # トークリストグリッドのメイン画面
│   ├── talk_page.dart         # 個別の会話ビュー
│   ├── widgets/               # 再利用可能なUIコンポーネント
│   │   ├── message.dart       # メッセージバブルウィジェット
│   │   ├── inline_image.dart  # ズーム対応フォトビューア
│   │   ├── inline_video.dart  # ビデオプレーヤーウィジェット
│   │   └── inline_audio.dart  # オーディオプレーヤーウィジェット
│   ├── menu/                  # メニュー関連ページ
│   │   ├── icon_change_page.dart  # トークアイコン変更
│   │   ├── call_me_page.dart      # 表示名設定
│   │   ├── favorites_page.dart    # お気に入りメッセージ表示
│   │   ├── media_page.dart        # メディアギャラリービュー
│   │   └── text_search_page.dart  # 検索機能
│   ├── dialogs/               # ダイアログウィジェット
│   │   └── file_picker_dialog.dart # ファイル選択ダイアログ
│   └── utils/                 # ヘルパークラス
│       ├── database_helper.dart   # SQLiteデータベース操作
│       ├── file_utils.dart        # ファイル管理ユーティリティ
│       ├── app_config.dart        # アプリ設定
│       └── helper.dart            # 汎用ユーティリティ
├── assets/                    # 静的アセット
├── android/                   # Android固有のコード
├── ios/                       # iOS固有のコード
└── pubspec.yaml              # 依存関係とプロジェクト設定
```

## 開発環境のセットアップ

### 前提条件

1. **Flutter SDKのインストール**
   - Flutter 3.3.4以上、4.0.0未満
   - [公式インストールガイド](https://flutter.dev/docs/get-started/install)を参照

2. **開発ツール**
   - Xcode（iOS開発用）
   - Android Studio（Android開発用）
   - VSCode または IntelliJ IDEA（推奨エディタ）

### セットアップ手順

1. **リポジトリのクローン**
   ```bash
   git clone [repository-url]
   cd msgviewer
   ```

2. **依存関係のインストール**
   ```bash
   flutter pub get
   ```

3. **Flutter環境の確認**
   ```bash
   flutter doctor
   ```

4. **デバイスの接続確認**
   ```bash
   flutter devices
   ```

5. **アプリの実行**
   ```bash
   flutter run
   ```

## 開発コマンド

### 基本コマンド
```bash
# アプリの実行
flutter run

# 依存関係の更新
flutter pub get

# コード解析
flutter analyze

# テストの実行
flutter test

# ビルドアーティファクトのクリーン
flutter clean
```

### ビルドコマンド
```bash
# iOSビルド
flutter build ios

# Android APKビルド
flutter build apk

# Android App Bundle
flutter build appbundle
```

### アイコン生成
```bash
# アプリランチャーアイコンの生成
flutter pub run flutter_launcher_icons
```

## データベース仕様

- **データベースファイル**: `app_data.db`
- **データベースバージョン**: 3
- **テーブル構成**:
  - `Messages`: メッセージデータ
  - `Talks`: トーク（会話）情報

## 主要な依存パッケージ

### UI関連
- `photo_view`: 画像のズーム表示
- `video_player`: 動画再生
- `just_audio`: 音声再生
- `table_calendar`: カレンダー表示

### データ処理
- `sqflite`: SQLiteデータベース
- `csv`: CSVファイル処理
- `archive`: ZIPファイル処理

### ファイル操作
- `path_provider`: アプリケーションディレクトリアクセス
- `file_picker`: ファイル選択
- `image_picker`: 画像選択
- `flutter_image_compress`: 画像圧縮

## データフロー

1. **インポート**: ZIPファイル選択 → アプリドキュメントへ展開 → CSV解析
2. **保存**: SQLiteへ挿入、ファイルパス管理 → `/media`サブフォルダへメディア整理
3. **表示**: データベースクエリ → ページネーション付きメッセージ読み込み → インラインメディア表示
4. **ナビゲーション**: ホーム（トークリスト）→ トークページ → 各種メニューオプション

## トラブルシューティング

### よくある問題と解決方法

1. **ビルドエラーが発生する場合**
   ```bash
   flutter clean
   flutter pub get
   flutter run
   ```

2. **iOS実機で実行できない場合**
   - Xcodeでプロジェクトを開き、Signing & Capabilitiesを設定
   - 開発者証明書の確認

3. **データベースエラー**
   - アプリをアンインストールして再インストール
   - データベースバージョンの確認

## 開発メモ

### コーディング規約
- Dartの標準的な命名規則に従う
- ウィジェットは小さく保つ
- 状態管理はStatefulWidgetを使用

### Git運用
- mainブランチがデフォルト
- 機能開発は feature/* ブランチで行う
- コミットメッセージは日本語可

### リリース準備
1. バージョン番号の更新（pubspec.yaml）
2. アイコンの生成
3. ビルドとテスト
4. リリースノートの作成

## 現在のバージョン

- **アプリバージョン**: 2.0.0+1
- **最終更新**: 開発中

## ライセンス

プライベートプロジェクト

## 連絡先

開発に関する質問や問題がある場合は、リポジトリのIssueを作成してください。