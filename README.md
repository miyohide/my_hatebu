# My Hatebu

URLをブックマークとして保存し、AWS Bedrock（生成AI）を使ってWebページの要約を自動生成するAPIアプリケーション。

## 機能概要

- URLを登録すると、Webページの内容を取得しAIが自動で要約を生成
- ブックマークの一覧表示、検索、削除
- APIキーによる認証
- レートリミット（Rack::Attack）
- SSRF対策（プライベートIPへのアクセスをブロック）

## 技術スタック

- Ruby 4.0.5
- Rails 8.1（APIモード）
- SQLite3（開発・テスト） / PostgreSQL（本番）
- AWS Bedrock Runtime（AI要約生成）
- Nokogiri（HTML解析）
- Kaminari（ページネーション）
- Rack::Attack（レートリミット）
- Kamal（デプロイ）

## 前提条件

- Ruby 4.0.5
- Bundler
- SQLite3（開発環境）
- AWSアカウント（Bedrock APIを利用する場合）

## セットアップ

### 1. リポジトリのクローン

```bash
git clone <repository-url>
cd my_hatebu
```

### 2. Gemのインストール

```bash
bundle install
```

### 3. 環境変数の設定

`.env.example` をコピーして `.env` を作成する。

```bash
cp .env.example .env
```

`.env` ファイルの内容を環境に合わせて編集する。

### 4. データベースの作成

```bash
bin/rails db:create db:migrate
```

### 5. サーバーの起動

```bash
bin/rails server
```

`http://localhost:3000` でAPIが利用可能になる。

## 環境変数

| 変数名 | 説明 | デフォルト値 | 必須 |
|--------|------|-------------|------|
| `API_KEY` | API認証用のキー。リクエスト時に `X-API-Key` ヘッダーに指定する | なし | はい |
| `AWS_REGION` | AWS Bedrockのリージョン | `us-east-1` | いいえ |
| `BEDROCK_MODEL_ID` | Bedrockで使用するモデルID | `google.gemma-3-27b-it` | いいえ |
| `RATE_LIMIT_PER_MINUTE` | 1分あたりのAPIリクエスト制限数（IPアドレスごと） | `10` | いいえ |
| `RAILS_LOG_LEVEL` | Railsのログレベル | `debug` | いいえ |
| `DATABASE_URL` | 本番環境のPostgreSQL接続URL | なし | 本番のみ |
| `RAILS_MASTER_KEY` | Rails暗号化キー（credentials用） | なし | 本番のみ |

### AWS認証情報

Bedrock APIの利用には、AWS認証情報の設定が必要。以下のいずれかの方法で設定する。

- 環境変数 `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`
- `~/.aws/credentials` ファイル
- IAMロール（EC2/ECS上で実行する場合）

## APIエンドポイント

すべてのAPIリクエストには `X-API-Key` ヘッダーが必要（ヘルスチェックを除く）。

### ブックマーク作成

```bash
curl -X POST http://localhost:3000/api/v1/bookmarks \
  -H "Content-Type: application/json" \
  -H "X-API-Key: your_api_key_here" \
  -d '{"url": "https://example.com/article"}'
```

### ブックマーク一覧

```bash
curl http://localhost:3000/api/v1/bookmarks \
  -H "X-API-Key: your_api_key_here"
```

ページネーションパラメータ: `page`, `per_page`（デフォルト20件）

### ブックマーク検索

```bash
curl "http://localhost:3000/api/v1/bookmarks/search?q=キーワード" \
  -H "X-API-Key: your_api_key_here"
```

### ブックマーク詳細

```bash
curl http://localhost:3000/api/v1/bookmarks/1 \
  -H "X-API-Key: your_api_key_here"
```

### ブックマーク削除

```bash
curl -X DELETE http://localhost:3000/api/v1/bookmarks/1 \
  -H "X-API-Key: your_api_key_here"
```

### ヘルスチェック

```bash
curl http://localhost:3000/health
```

認証不要。`{"status": "ok"}` を返す。

## テストの実行

```bash
bin/rails test
```

## Lint（静的解析）

```bash
bin/rubocop
```

## セキュリティスキャン

```bash
bin/brakeman --no-pager
bin/bundler-audit
```

## Docker での実行

```bash
docker build -t my_hatebu .
docker run -d -p 80:80 \
  -e RAILS_MASTER_KEY=<master.keyの値> \
  -e API_KEY=<APIキー> \
  -e DATABASE_URL=<PostgreSQL接続URL> \
  --name my_hatebu my_hatebu
```

## デプロイ（Kamal）

Kamalを使用した本番デプロイに対応している。設定は `config/deploy.yml` を参照。

```bash
kamal setup   # 初回セットアップ
kamal deploy  # デプロイ
```

## レートリミット

- `/api/` 以下のエンドポイントに対して、IPアドレスごとに1分あたり最大リクエスト数を制限
- 制限を超えた場合、HTTPステータス429と以下のJSONが返る

```json
{
  "error": {
    "code": "rate_limit_exceeded",
    "message": "リクエスト数が制限を超えました。しばらく待ってから再試行してください"
  }
}
```

## ライセンス

このプロジェクトのライセンスについてはリポジトリのライセンスファイルを参照。
