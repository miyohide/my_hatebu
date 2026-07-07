# ブックマークサービス 詳細設計書

## 目次

1. [システムアーキテクチャ](#1-システムアーキテクチャ)
2. [詳細設計](#2-詳細設計)
3. [外部サービス連携](#3-外部サービス連携)
4. [エラーハンドリング](#4-エラーハンドリング)
5. [設定管理](#5-設定管理)

---

## 1. システムアーキテクチャ

### 1.1 全体構成図

```
┌─────────────┐       ┌──────────────────────────────────────────┐
│   Client    │       │           Docker Compose                  │
│  (curl等)   │       │                                          │
└──────┬──────┘       │  ┌────────────────────────────────────┐  │
       │ HTTP         │  │         Rails API (port 3000)       │  │
       │              │  │                                      │  │
       ▼              │  │  ┌──────────┐  ┌─────────────────┐  │  │
  ┌────────────┐      │  │  │Controller│→ │    Service層     │  │  │
  │  Rack      │──────┼──┤  └──────────┘  │                 │  │  │
  │  Attack    │      │  │                 │ ・WebFetcher    │  │  │
  │(Rate Limit)│      │  │  ┌──────────┐  │ ・Summarizer    │  │  │
  └────────────┘      │  │  │  Model   │← │ ・BookmarkCreator│ │  │
                      │  │  └────┬─────┘  └────────┬────────┘  │  │
                      │  │       │                  │           │  │
                      │  └───────┼──────────────────┼───────────┘  │
                      │          │                  │              │
                      │          ▼                  ▼              │
                      │  ┌──────────────┐  ┌──────────────────┐   │
                      │  │ PostgreSQL   │  │  外部サービス     │   │
                      │  │ (port 5432)  │  │  ・Amazon Bedrock │   │
                      │  └──────────────┘  │  ・対象Webページ  │   │
                      │                    └──────────────────┘   │
                      └───────────────────────────────────────────┘
```

### 1.2 コンポーネント一覧と責務

| コンポーネント | 責務 |
|--------------|------|
| Rack::Attack | レートリミット制御（1分あたり10リクエスト） |
| ApiKeyAuthenticator | X-API-Keyヘッダーによる認証処理 |
| BookmarksController | APIリクエストの受付とレスポンス返却 |
| BookmarkCreatorService | ブックマーク登録のオーケストレーション |
| WebFetcherService | 対象URLのWebページ取得とHTML解析 |
| SummarizerService | Amazon Bedrockを利用したテキスト要約生成 |
| Bookmark (Model) | データの永続化、バリデーション、検索クエリ |
| PostgreSQL | データストア |
| Amazon Bedrock | AI要約生成（Claude モデル） |

---

## 2. 詳細設計

### 2.1 ディレクトリ構成

```
my_hatebu/
├── app/
│   ├── controllers/
│   │   ├── application_controller.rb
│   │   ├── concerns/
│   │   │   └── api_key_authenticatable.rb
│   │   └── api/
│   │       └── v1/
│   │           └── bookmarks_controller.rb
│   ├── models/
│   │   ├── application_record.rb
│   │   └── bookmark.rb
│   └── services/
│       ├── bookmark_creator_service.rb
│       ├── web_fetcher_service.rb
│       └── summarizer_service.rb
├── config/
│   ├── initializers/
│   │   ├── rack_attack.rb
│   │   └── bedrock.rb
│   ├── routes.rb
│   └── database.yml
├── db/
│   ├── migrate/
│   │   └── YYYYMMDDHHMMSS_create_bookmarks.rb
│   └── schema.rb
├── spec/
│   ├── requests/
│   │   └── api/v1/bookmarks_spec.rb
│   ├── models/
│   │   └── bookmark_spec.rb
│   └── services/
│       ├── bookmark_creator_service_spec.rb
│       ├── web_fetcher_service_spec.rb
│       └── summarizer_service_spec.rb
├── Dockerfile
├── docker-compose.yml
├── Gemfile
└── .env.example
```

### 2.2 主要クラス/モジュール設計

#### 2.2.1 ApiKeyAuthenticatable（Concern）

```ruby
# app/controllers/concerns/api_key_authenticatable.rb
module ApiKeyAuthenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_api_key!
  end

  private

  def authenticate_api_key!
    api_key = request.headers["X-API-Key"]
    unless api_key.present? && ActiveSupport::SecurityUtils.secure_compare(api_key, ENV["API_KEY"])
      render json: { error: "Unauthorized" }, status: :unauthorized
    end
  end
end
```

#### 2.2.2 BookmarksController

```ruby
# app/controllers/api/v1/bookmarks_controller.rb
module Api
  module V1
    class BookmarksController < ApplicationController
      include ApiKeyAuthenticatable

      # POST /api/v1/bookmarks
      def create
        result = BookmarkCreatorService.new(params[:url]).call
        if result.success?
          render json: BookmarkSerializer.new(result.bookmark), status: :created
        else
          render json: { error: result.error }, status: result.status
        end
      end

      # GET /api/v1/bookmarks
      def index
        bookmarks = Bookmark.order(created_at: :desc)
                            .page(params[:page])
                            .per(params[:per_page] || 20)
        render json: {
          bookmarks: BookmarkSerializer.new(bookmarks),
          meta: pagination_meta(bookmarks)
        }
      end

      # GET /api/v1/bookmarks/:id
      def show
        bookmark = Bookmark.find(params[:id])
        render json: BookmarkSerializer.new(bookmark)
      end

      # DELETE /api/v1/bookmarks/:id
      def destroy
        bookmark = Bookmark.find(params[:id])
        bookmark.destroy!
        head :no_content
      end

      # GET /api/v1/bookmarks/search
      def search
        bookmarks = Bookmark.search(params[:q])
                            .order(created_at: :desc)
                            .page(params[:page])
                            .per(params[:per_page] || 20)
        render json: {
          bookmarks: BookmarkSerializer.new(bookmarks),
          meta: pagination_meta(bookmarks)
        }
      end
    end
  end
end
```

#### 2.2.3 Bookmark モデル

```ruby
# app/models/bookmark.rb
class Bookmark < ApplicationRecord
  validates :url, presence: true, uniqueness: true
  validates :url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }

  scope :search, ->(query) {
    where("title ILIKE :q OR summary ILIKE :q", q: "%#{sanitize_sql_like(query)}%")
  }

  # URL正規化（末尾スラッシュの統一、フラグメント除去）
  before_validation :normalize_url

  private

  def normalize_url
    return if url.blank?
    uri = URI.parse(url)
    uri.fragment = nil
    self.url = uri.to_s.chomp("/")
  rescue URI::InvalidURIError
    # バリデーションで弾く
  end
end
```

#### 2.2.4 BookmarkCreatorService

```ruby
# app/services/bookmark_creator_service.rb
class BookmarkCreatorService
  Result = Struct.new(:success?, :bookmark, :error, :status, keyword_init: true)

  def initialize(url)
    @url = url
  end

  def call
    # 1. URL形式バリデーション
    return Result.new(success?: false, error: "URLが無効です", status: :unprocessable_entity) unless valid_url?

    # 2. 重複チェック
    if Bookmark.exists?(url: normalize(@url))
      return Result.new(success?: false, error: "このURLは既に登録されています", status: :conflict)
    end

    # 3. Webページ取得
    fetch_result = WebFetcherService.new(@url).call

    # 4. AI要約生成（ページ取得成功時のみ）
    summary = nil
    if fetch_result.success?
      summary = SummarizerService.new(fetch_result.body_text).call
    end

    # 5. データベース保存
    bookmark = Bookmark.create!(
      url: normalize(@url),
      title: fetch_result.title || "",
      summary: summary || ""
    )

    Result.new(success?: true, bookmark: bookmark)
  rescue ActiveRecord::RecordInvalid => e
    Result.new(success?: false, error: e.message, status: :unprocessable_entity)
  end

  private

  def valid_url?
    uri = URI.parse(@url)
    uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
  rescue URI::InvalidURIError
    false
  end

  def normalize(url)
    uri = URI.parse(url)
    uri.fragment = nil
    uri.to_s.chomp("/")
  end
end
```

#### 2.2.5 WebFetcherService

```ruby
# app/services/web_fetcher_service.rb
class WebFetcherService
  Result = Struct.new(:success?, :title, :body_text, :error, keyword_init: true)

  MAX_REDIRECTS = 5
  TIMEOUT = 10
  USER_AGENT = "MyHatebuBot/1.0"

  def initialize(url)
    @url = url
  end

  def call
    response = fetch_with_redirects(@url)
    doc = Nokogiri::HTML(response.body)

    title = extract_title(doc)
    body_text = extract_body_text(doc)

    Result.new(success?: true, title: title, body_text: body_text)
  rescue StandardError => e
    Rails.logger.error("WebFetcher failed: #{e.message}")
    Result.new(success?: false, error: e.message)
  end

  private

  def fetch_with_redirects(url, redirect_count = 0)
    raise "リダイレクト回数が上限を超えました" if redirect_count > MAX_REDIRECTS

    uri = URI.parse(url)
    validate_not_private_ip!(uri)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = TIMEOUT
    http.read_timeout = TIMEOUT

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = USER_AGENT

    response = http.request(request)

    case response
    when Net::HTTPRedirection
      fetch_with_redirects(response["location"], redirect_count + 1)
    when Net::HTTPSuccess
      response
    else
      raise "HTTP #{response.code}: #{response.message}"
    end
  end

  def validate_not_private_ip!(uri)
    ip = IPAddr.new(Resolv.getaddress(uri.host))
    if ip.private? || ip.loopback? || ip.link_local?
      raise "プライベートIPアドレスへのアクセスは許可されていません"
    end
  end

  def extract_title(doc)
    # OGPタグ優先、なければtitleタグ
    doc.at_css('meta[property="og:title"]')&.[]("content") ||
      doc.at_css("title")&.text&.strip
  end

  def extract_body_text(doc)
    # スクリプト・スタイルタグを除去してテキスト抽出
    doc.css("script, style, nav, header, footer").remove
    doc.css("body").text.gsub(/\s+/, " ").strip.truncate(10_000)
  end
end
```

#### 2.2.6 SummarizerService

```ruby
# app/services/summarizer_service.rb
class SummarizerService
  MODEL_ID = "anthropic.claude-3-haiku-20240307-v1:0"
  MAX_INPUT_LENGTH = 8_000

  def initialize(text)
    @text = text.truncate(MAX_INPUT_LENGTH)
  end

  def call
    client = Aws::BedrockRuntime::Client.new(
      region: ENV.fetch("AWS_REGION", "us-east-1")
    )

    response = client.converse(
      model_id: MODEL_ID,
      messages: [
        {
          role: "user",
          content: [{ text: prompt }]
        }
      ],
      inference_config: {
        max_tokens: 1024,
        temperature: 0.3
      }
    )

    response.output.message.content[0].text
  rescue Aws::BedrockRuntime::Errors::ServiceError => e
    Rails.logger.error("Bedrock API error: #{e.message}")
    nil
  end

  private

  def prompt
    <<~PROMPT
      以下のWebページの内容を日本語で200〜400文字程度に要約してください。
      要点を箇条書きではなく、自然な文章でまとめてください。

      ---
      #{@text}
    PROMPT
  end
end
```

### 2.3 ブックマーク登録のシーケンスフロー

```
Client          Controller       CreatorService    WebFetcher     Summarizer      DB
  │                  │                 │               │              │            │
  │ POST /bookmarks  │                 │               │              │            │
  ├─────────────────►│                 │               │              │            │
  │                  │ authenticate    │               │              │            │
  │                  ├──(API Key確認)──┤               │              │            │
  │                  │                 │               │              │            │
  │                  │ call(url)       │               │              │            │
  │                  ├────────────────►│               │              │            │
  │                  │                 │ validate url  │              │            │
  │                  │                 ├───────────────┤              │            │
  │                  │                 │               │              │            │
  │                  │                 │ check duplicate               │            │
  │                  │                 ├──────────────────────────────────────────►│
  │                  │                 │◄─────────────────────────────────────────┤
  │                  │                 │               │              │            │
  │                  │                 │ fetch(url)    │              │            │
  │                  │                 ├──────────────►│              │            │
  │                  │                 │  title, text  │              │            │
  │                  │                 │◄──────────────┤              │            │
  │                  │                 │               │              │            │
  │                  │                 │ summarize(text)│             │            │
  │                  │                 ├──────────────────────────────►│           │
  │                  │                 │               │   summary    │            │
  │                  │                 │◄─────────────────────────────┤            │
  │                  │                 │               │              │            │
  │                  │                 │ save bookmark │              │            │
  │                  │                 ├──────────────────────────────────────────►│
  │                  │                 │               │              │   saved    │
  │                  │                 │◄─────────────────────────────────────────┤
  │                  │                 │               │              │            │
  │                  │  Result(bookmark)│              │              │            │
  │                  │◄────────────────┤               │              │            │
  │  201 Created     │                 │               │              │            │
  │◄─────────────────┤                 │               │              │            │
```

### 2.4 データベーススキーマ（マイグレーション）

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_bookmarks.rb
class CreateBookmarks < ActiveRecord::Migration[8.1]
  def change
    create_table :bookmarks do |t|
      t.text :url, null: false
      t.text :title, default: ""
      t.text :summary, default: ""

      t.timestamps
    end

    add_index :bookmarks, :url, unique: true
    add_index :bookmarks, :created_at, order: { created_at: :desc }
  end
end
```

#### インデックス戦略

| インデックス | 対象カラム | 目的 |
|------------|-----------|------|
| index_bookmarks_on_url | url (UNIQUE) | 重複チェックの高速化、一意性保証 |
| index_bookmarks_on_created_at | created_at (DESC) | 一覧表示の降順ソート高速化 |

検索機能については、初期段階では `ILIKE` による部分一致検索を採用する。データ量が増加した場合は PostgreSQL の全文検索（`pg_trgm` 拡張）への移行を検討する。

### 2.5 API リクエスト/レスポンス形式

#### POST /api/v1/bookmarks（ブックマーク登録）

**リクエスト:**

```http
POST /api/v1/bookmarks HTTP/1.1
Content-Type: application/json
X-API-Key: your-api-key-here

{
  "url": "https://example.com/article/123"
}
```

**レスポンス（201 Created）:**

```json
{
  "bookmark": {
    "id": 1,
    "url": "https://example.com/article/123",
    "title": "記事タイトル",
    "summary": "この記事はRuby on Railsの新機能について解説している。主要な変更点として...",
    "created_at": "2024-01-15T10:30:00Z",
    "updated_at": "2024-01-15T10:30:00Z"
  }
}
```

#### GET /api/v1/bookmarks（一覧取得）

**リクエスト:**

```http
GET /api/v1/bookmarks?page=1&per_page=20 HTTP/1.1
X-API-Key: your-api-key-here
```

**レスポンス（200 OK）:**

```json
{
  "bookmarks": [
    {
      "id": 1,
      "url": "https://example.com/article/123",
      "title": "記事タイトル",
      "summary": "要約テキスト...",
      "created_at": "2024-01-15T10:30:00Z",
      "updated_at": "2024-01-15T10:30:00Z"
    }
  ],
  "meta": {
    "current_page": 1,
    "total_pages": 5,
    "total_count": 98,
    "per_page": 20
  }
}
```

#### GET /api/v1/bookmarks/:id（詳細取得）

**リクエスト:**

```http
GET /api/v1/bookmarks/1 HTTP/1.1
X-API-Key: your-api-key-here
```

**レスポンス（200 OK）:**

```json
{
  "bookmark": {
    "id": 1,
    "url": "https://example.com/article/123",
    "title": "記事タイトル",
    "summary": "この記事はRuby on Railsの新機能について解説している。主要な変更点として...",
    "created_at": "2024-01-15T10:30:00Z",
    "updated_at": "2024-01-15T10:30:00Z"
  }
}
```

#### DELETE /api/v1/bookmarks/:id（削除）

**リクエスト:**

```http
DELETE /api/v1/bookmarks/1 HTTP/1.1
X-API-Key: your-api-key-here
```

**レスポンス（204 No Content）:**

レスポンスボディなし。

#### GET /api/v1/bookmarks/search（検索）

**リクエスト:**

```http
GET /api/v1/bookmarks/search?q=Rails&page=1&per_page=20 HTTP/1.1
X-API-Key: your-api-key-here
```

**レスポンス（200 OK）:**

```json
{
  "bookmarks": [
    {
      "id": 1,
      "url": "https://example.com/article/123",
      "title": "Rails 8.1の新機能",
      "summary": "Rails 8.1で追加された新機能について...",
      "created_at": "2024-01-15T10:30:00Z",
      "updated_at": "2024-01-15T10:30:00Z"
    }
  ],
  "meta": {
    "current_page": 1,
    "total_pages": 1,
    "total_count": 3,
    "per_page": 20
  }
}
```

---

## 3. 外部サービス連携

### 3.1 Amazon Bedrock の呼び出し方法

#### 使用モデル

- モデルID: `anthropic.claude-3-haiku-20240307-v1:0`
- 選定理由: 要約タスクに十分な性能を持ち、コストが低い。レスポンス速度も速い。

#### 呼び出しフロー

1. `aws-sdk-bedrockruntime` gem の `Aws::BedrockRuntime::Client` を利用
2. Converse API（`client.converse`）を使用してメッセージを送信
3. IAM認証情報は環境変数（`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`）または IAM ロールで管理

#### API呼び出しパラメータ

```ruby
{
  model_id: "anthropic.claude-3-haiku-20240307-v1:0",
  messages: [
    { role: "user", content: [{ text: prompt }] }
  ],
  inference_config: {
    max_tokens: 1024,      # 要約に十分なトークン数
    temperature: 0.3       # 安定した出力のため低めに設定
  }
}
```

#### 入力テキストの制限

- Webページから抽出したテキストは最大8,000文字に切り詰めてからAPIに送信
- これによりトークン使用量を制御し、コストを抑制する

#### 認証方式

開発環境では環境変数による認証を使用する:

```
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
AWS_REGION=us-east-1
```

本番環境ではIAMロールによる認証を推奨する。

### 3.2 Webページ取得の実装方針

#### 使用ライブラリ

| ライブラリ | 用途 |
|-----------|------|
| net/http (標準ライブラリ) | HTTPリクエスト |
| nokogiri | HTML解析、DOM操作 |
| resolv (標準ライブラリ) | DNS解決（SSRF防止） |
| ipaddr (標準ライブラリ) | IPアドレス判定 |

#### セキュリティ対策（SSRF防止）

プライベートIPアドレスへのリクエストを防止するため、DNS解決後にIPアドレスを検証する:

- `10.0.0.0/8` — プライベートネットワーク
- `172.16.0.0/12` — プライベートネットワーク
- `192.168.0.0/16` — プライベートネットワーク
- `127.0.0.0/8` — ループバック
- `169.254.0.0/16` — リンクローカル

#### HTML解析の方針

1. `og:title` メタタグからタイトルを優先取得
2. `og:title` がない場合は `<title>` タグから取得
3. 本文テキストは `<script>`, `<style>`, `<nav>`, `<header>`, `<footer>` を除去してから抽出
4. 抽出テキストは空白を正規化し、10,000文字に制限

#### HTTPリクエスト設定

| 設定項目 | 値 | 理由 |
|---------|-----|------|
| タイムアウト（接続） | 10秒 | 応答しないサーバーでの待機防止 |
| タイムアウト（読取） | 10秒 | 大容量レスポンスでの待機防止 |
| リダイレクト上限 | 5回 | 無限リダイレクトループ防止 |
| User-Agent | MyHatebuBot/1.0 | クローラーとして適切に識別 |

---

## 4. エラーハンドリング

### 4.1 エラーレスポンス形式

すべてのエラーレスポンスは統一されたJSON形式で返却する:

```json
{
  "error": {
    "code": "error_code",
    "message": "人間が読めるエラーメッセージ"
  }
}
```

#### HTTPステータスコードとエラーコード一覧

| ステータス | エラーコード | 発生条件 |
|-----------|------------|---------|
| 400 Bad Request | `invalid_request` | リクエストボディの形式不正、必須パラメータ欠落 |
| 401 Unauthorized | `unauthorized` | APIキーが未指定または不正 |
| 404 Not Found | `not_found` | 指定IDのブックマークが存在しない |
| 409 Conflict | `duplicate_url` | 同一URLが既に登録済み |
| 422 Unprocessable Entity | `invalid_url` | URLの形式が不正 |
| 429 Too Many Requests | `rate_limit_exceeded` | レートリミット超過 |
| 500 Internal Server Error | `internal_error` | 予期しないサーバーエラー |
| 503 Service Unavailable | `service_unavailable` | 外部サービス（Bedrock）の一時的な障害 |

#### ApplicationControllerでの共通エラーハンドリング

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::API
  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from ActionController::ParameterMissing, with: :bad_request

  private

  def not_found
    render json: { error: { code: "not_found", message: "リソースが見つかりません" } }, status: :not_found
  end

  def bad_request(exception)
    render json: { error: { code: "invalid_request", message: exception.message } }, status: :bad_request
  end
end
```

### 4.2 リトライ戦略

#### Webページ取得のリトライ

| 項目 | 設定値 |
|------|-------|
| 最大リトライ回数 | 2回（初回 + 2回リトライ = 合計3回） |
| リトライ間隔 | 指数バックオフ（1秒、2秒） |
| リトライ対象 | タイムアウト、5xx系エラー |
| リトライ対象外 | 4xx系エラー（クライアントエラー）、DNS解決失敗 |

```ruby
# WebFetcherService内でのリトライ実装
def fetch_with_retry(url)
  retries = 0
  begin
    fetch_with_redirects(url)
  rescue Net::OpenTimeout, Net::ReadTimeout, Net::HTTPServerError => e
    retries += 1
    if retries <= 2
      sleep(retries) # 指数バックオフ: 1秒, 2秒
      retry
    end
    raise e
  end
end
```

#### Amazon Bedrock のリトライ

| 項目 | 設定値 |
|------|-------|
| 最大リトライ回数 | 3回 |
| リトライ間隔 | 指数バックオフ（AWS SDKのデフォルト設定を利用） |
| リトライ対象 | ThrottlingException、ServiceUnavailableException |
| リトライ対象外 | ValidationException、AccessDeniedException |

AWS SDK はデフォルトでリトライ機能を持つため、基本的にはSDKの設定に委ねる:

```ruby
Aws::BedrockRuntime::Client.new(
  region: ENV.fetch("AWS_REGION", "us-east-1"),
  retry_limit: 3,
  retry_backoff: ->(context) { sleep(2**context.retries) }
)
```

#### 障害時の挙動方針（Graceful Degradation）

外部サービスの障害時も、可能な限りブックマーク登録自体は成功させる:

| 障害箇所 | 挙動 |
|---------|------|
| Webページ取得失敗 | タイトル・要約を空文字で登録し、201を返す |
| Bedrock API失敗 | 要約を空文字で登録し、201を返す |
| データベース障害 | 500エラーを返す（リトライ不可） |

---

## 5. 設定管理

### 5.1 環境変数一覧

| 環境変数名 | 必須 | デフォルト値 | 説明 |
|-----------|------|------------|------|
| `DATABASE_URL` | ○ | — | PostgreSQL接続文字列 |
| `API_KEY` | ○ | — | APIアクセス用の認証キー |
| `AWS_ACCESS_KEY_ID` | ○ | — | AWS認証（アクセスキーID） |
| `AWS_SECRET_ACCESS_KEY` | ○ | — | AWS認証（シークレットキー） |
| `AWS_REGION` | — | `us-east-1` | AWSリージョン |
| `BEDROCK_MODEL_ID` | — | `anthropic.claude-3-haiku-20240307-v1:0` | 使用するBedrockモデルID |
| `RAILS_ENV` | — | `development` | Rails実行環境 |
| `RAILS_LOG_LEVEL` | — | `info` | ログレベル |
| `RATE_LIMIT_PER_MINUTE` | — | `10` | 1分あたりのリクエスト上限 |

#### .env.example

```env
# データベース
DATABASE_URL=postgresql://postgres:password@db:5432/my_hatebu_development

# 認証
API_KEY=your-secret-api-key-here

# AWS / Amazon Bedrock
AWS_ACCESS_KEY_ID=your-access-key-id
AWS_SECRET_ACCESS_KEY=your-secret-access-key
AWS_REGION=us-east-1
BEDROCK_MODEL_ID=anthropic.claude-3-haiku-20240307-v1:0

# Rails
RAILS_ENV=development
RAILS_LOG_LEVEL=info

# レートリミット
RATE_LIMIT_PER_MINUTE=10
```

### 5.2 Docker Compose 構成

```yaml
# docker-compose.yml
version: "3.8"

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "3000:3000"
    depends_on:
      db:
        condition: service_healthy
    environment:
      - DATABASE_URL=postgresql://postgres:password@db:5432/my_hatebu_development
      - API_KEY=${API_KEY}
      - AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
      - AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
      - AWS_REGION=${AWS_REGION:-us-east-1}
      - BEDROCK_MODEL_ID=${BEDROCK_MODEL_ID:-anthropic.claude-3-haiku-20240307-v1:0}
    volumes:
      - .:/app
      - bundle_cache:/usr/local/bundle
    command: bash -c "rm -f tmp/pids/server.pid && bundle exec rails server -b 0.0.0.0"

  db:
    image: postgres:16
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
      POSTGRES_DB: my_hatebu_development
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

volumes:
  postgres_data:
  bundle_cache:
```

#### Dockerfile

```dockerfile
# Dockerfile
FROM ruby:4.0-slim

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
```

### 5.3 Rack::Attack 設定

```ruby
# config/initializers/rack_attack.rb
class Rack::Attack
  # 1分あたりのリクエスト制限
  throttle("api/ip", limit: ENV.fetch("RATE_LIMIT_PER_MINUTE", 10).to_i, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/api/")
  end

  # レートリミット超過時のレスポンス
  self.throttled_responder = lambda do |_request|
    [
      429,
      { "Content-Type" => "application/json" },
      [{ error: { code: "rate_limit_exceeded", message: "リクエスト数の上限を超えました。しばらく待ってから再試行してください。" } }.to_json]
    ]
  end
end
```

### 5.4 ルーティング設定

```ruby
# config/routes.rb
Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :bookmarks, only: [:create, :index, :show, :destroy] do
        collection do
          get :search
        end
      end
    end
  end

  # ヘルスチェック
  get "/health", to: proc { [200, { "Content-Type" => "application/json" }, ['{"status":"ok"}']] }
end
```

### 5.5 Gemfile（主要な依存関係）

```ruby
# Gemfile
source "https://rubygems.org"

ruby "4.0.5"

gem "rails", "~> 8.1.3"
gem "pg", "~> 1.5"
gem "puma", ">= 5.0"

# AWS
gem "aws-sdk-bedrockruntime", "~> 1.0"

# HTML解析
gem "nokogiri", "~> 1.16"

# ページネーション
gem "kaminari", "~> 1.2"

# レートリミット
gem "rack-attack", "~> 6.7"

# 環境変数管理
gem "dotenv-rails", groups: [:development, :test]

group :development, :test do
  gem "rspec-rails", "~> 6.1"
  gem "factory_bot_rails", "~> 6.4"
  gem "webmock", "~> 3.19"
  gem "rubocop", "~> 1.60", require: false
  gem "rubocop-rails", "~> 2.23", require: false
  gem "rubocop-rspec", "~> 2.25", require: false
end
```

---

## 補足: 今後の拡張可能性

| 項目 | 説明 |
|------|------|
| 非同期要約生成 | Sidekiq を導入し、要約生成をバックグラウンドジョブ化 |
| 全文検索 | PostgreSQL の `pg_trgm` 拡張または Elasticsearch 導入 |
| タグ機能 | ブックマークへのタグ付け、タグによる絞り込み |
| 要約の再生成 | 登録済みブックマークの要約を再生成するエンドポイント追加 |
| Webフック | ブックマーク登録時に外部サービスへ通知 |
