# ブックマークサービス 実装タスク一覧

## 1. プロジェクト初期セットアップ

### 1.1 Railsプロジェクトの作成

- [x] `rails new my_hatebu --api` でプロジェクトを生成する（デフォルトでsqlite3を使用）
- [x] Ruby 4.0.5 を `.ruby-version` に指定する
- [x] 不要なデフォルトファイル（mailer、job等）を削除する

**受け入れ基準:**
- `rails -v` で Rails 8.1.x が表示される
- APIモードで起動し、`/` へのリクエストに応答できる

### 1.2 Gemfileの整備

- [x] `sqlite3`、`puma` の確認
- [x] `pg` を production グループに追加する
- [x] `aws-sdk-bedrockruntime` を追加する
- [x] `nokogiri` を追加する
- [x] `kaminari` を追加する
- [x] `rack-attack` を追加する
- [x] `dotenv-rails` を development/test グループに追加する
- [x] `webmock` を development/test グループに追加する
- [x] `rubocop`、`rubocop-rails`、`rubocop-minitest` を development/test グループに追加する
- [x] `bundle install` が成功する

**受け入れ基準:**
- `bundle install` がエラーなく完了する
- Gemfile.lock が生成される
- 全ての必要なgemが正しいバージョンでインストールされる

### 1.3 開発環境の整備

- [x] `.env.example` を作成する（API_KEY、AWS認証情報のテンプレート）
- [x] `config/database.yml` で development/test は sqlite3、production は postgresql を設定する
- [x] `storage/` ディレクトリが `.gitignore` に含まれていることを確認する

**受け入れ基準:**
- `bin/rails db:create db:migrate` でSQLite3データベースが作成される
- 外部DBサーバーなしで `bin/rails server` が起動する
- `.env.example` に必要な環境変数が記載されている

### 1.4 Minitest の初期設定

- [x] `test/test_helper.rb` に WebMock の設定（外部通信の禁止）を追加する
- [x] `test/fixtures/` ディレクトリにフィクスチャファイルを配置する
- [x] テスト用ヘルパーメソッド（API認証ヘッダー付与等）を定義する

**受け入れ基準:**
- `bin/rails test` がエラーなく実行できる（テスト0件で正常終了）
- WebMock による外部通信のブロックが有効である

---

## 2. データベース設計とマイグレーション

### 2.1 database.yml の設定

- [x] development/test 環境で sqlite3 アダプタが設定されていることを確認する
- [x] production 環境で postgresql アダプタと `DATABASE_URL` が設定されていることを確認する
- [x] `storage/` ディレクトリが存在することを確認する

**受け入れ基準:**
- development 環境で `rails db:create` が成功し、`storage/development.sqlite3` が生成される
- test 環境で `rails db:create` が成功し、`storage/test.sqlite3` が生成される
- production 環境では `DATABASE_URL` を参照する設定になっている

### 2.2 bookmarks テーブルのマイグレーション作成

- [x] `rails generate migration CreateBookmarks` でマイグレーションを作成する
- [x] `url`（text, NOT NULL）カラムを追加する
- [x] `title`（text, デフォルト空文字）カラムを追加する
- [x] `summary`（text, デフォルト空文字）カラムを追加する
- [x] `timestamps` を追加する
- [x] `url` カラムにユニークインデックスを追加する
- [x] `created_at` カラムに降順インデックスを追加する

**受け入れ基準:**
- `rails db:migrate` がエラーなく完了する
- `schema.rb` に bookmarks テーブルが正しく定義される
- URL のユニーク制約が動作する（重複挿入でエラーになる）
- インデックスが2つ（url, created_at）作成されている

---

## 3. Bookmark モデルの実装

### 3.1 モデルファイルの作成

- [x] `app/models/bookmark.rb` を作成する
- [x] `url` の presence バリデーションを追加する
- [x] `url` の uniqueness バリデーションを追加する
- [x] `url` の format バリデーション（HTTP/HTTPS のみ許可）を追加する
- [x] `before_validation` でURL正規化処理を実装する（末尾スラッシュ除去、フラグメント除去）

**受け入れ基準:**
- 有効なURLでブックマークを作成できる
- URLが空の場合バリデーションエラーになる
- 不正なURL形式の場合バリデーションエラーになる
- 同じURLの重複登録ができない
- 末尾スラッシュやフラグメントが正規化される

### 3.2 検索スコープの実装

- [x] `search` スコープを定義する（LIKE による部分一致検索）
- [x] タイトルと要約の両方を検索対象とする
- [x] `sanitize_sql_like` でSQLインジェクション対策を行う

**受け入れ基準:**
- キーワードでタイトルを検索できる
- キーワードで要約を検索できる
- 部分一致で検索結果が返る

---

## 4. WebFetcherService の実装

### 4.1 基本構造の作成

- [x] `app/services/web_fetcher_service.rb` を作成する
- [x] Result 構造体（success?, title, body_text, error）を定義する
- [x] コンストラクタでURLを受け取る設計にする

**受け入れ基準:**
- サービスオブジェクトとしてインスタンス化できる
- `call` メソッドで Result を返す

### 4.2 HTTP通信処理の実装

- [x] Net::HTTP を使用したHTTPリクエスト処理を実装する
- [x] タイムアウト設定（接続10秒、読取10秒）を行う
- [x] User-Agent ヘッダー（`MyHatebuBot/1.0`）を設定する
- [x] リダイレクト追従処理を実装する（最大5回）
- [x] HTTPS 対応を実装する

**受け入れ基準:**
- HTTP/HTTPS の URL からページを取得できる
- リダイレクトに追従する（最大5回まで）
- 6回以上のリダイレクトでエラーを返す
- タイムアウト時にエラーを返す

### 4.3 SSRF防止の実装

- [x] DNS解決後にIPアドレスを検証する処理を追加する
- [x] プライベートIP（10.x, 172.16.x, 192.168.x）へのアクセスを拒否する
- [x] ループバック（127.x）へのアクセスを拒否する
- [x] リンクローカル（169.254.x）へのアクセスを拒否する

**受け入れ基準:**
- プライベートIPアドレスへのリクエストがブロックされる
- ループバックアドレスへのリクエストがブロックされる
- 公開IPアドレスへのリクエストは許可される

### 4.4 HTML解析処理の実装

- [x] Nokogiri を使用したHTML解析処理を実装する
- [x] タイトル抽出（og:title 優先、fallback で title タグ）を実装する
- [x] 本文テキスト抽出（script/style/nav/header/footer 除去）を実装する
- [x] 抽出テキストの空白正規化と10,000文字制限を追加する

**受け入れ基準:**
- og:title がある場合はそれをタイトルとして返す
- og:title がない場合は title タグの内容を返す
- 不要なタグ（script, style等）を除去した本文テキストを返す
- テキストが10,000文字を超える場合は切り詰められる

### 4.5 リトライ処理の実装

- [x] タイムアウト時のリトライ処理を追加する（最大2回リトライ）
- [x] 5xx系エラー時のリトライ処理を追加する
- [x] 指数バックオフ（1秒、2秒）を実装する
- [x] 4xx系エラーではリトライしない制御を追加する

**受け入れ基準:**
- タイムアウト時に最大3回（初回+2回リトライ）試行する
- リトライ間隔が指数バックオフになっている
- 4xx エラーではリトライせず即座にエラーを返す

---

## 5. SummarizerService の実装

### 5.1 基本構造の作成

- [x] `app/services/summarizer_service.rb` を作成する
- [x] コンストラクタでテキストを受け取り、8,000文字に切り詰める
- [x] `call` メソッドで要約テキスト（またはnil）を返す設計にする

**受け入れ基準:**
- サービスオブジェクトとしてインスタンス化できる
- 8,000文字を超えるテキストが切り詰められる

### 5.2 Amazon Bedrock 呼び出しの実装

- [x] `Aws::BedrockRuntime::Client` の初期化処理を実装する
- [x] Converse API を使用したメッセージ送信処理を実装する
- [x] モデルID を環境変数から取得する（デフォルト: `anthropic.claude-3-haiku-20240307-v1:0`）
- [x] inference_config（max_tokens: 1024, temperature: 0.3）を設定する
- [x] リトライ設定（retry_limit: 3, 指数バックオフ）を追加する

**受け入れ基準:**
- Bedrock API を呼び出して要約テキストを取得できる
- 環境変数でモデルIDを変更できる
- リトライが設定されている

### 5.3 プロンプト設計

- [x] 日本語で200〜400文字の要約を生成するプロンプトを作成する
- [x] 箇条書きではなく自然な文章で要約するよう指示する
- [x] 英語ページでも日本語で要約するよう指示する

**受け入れ基準:**
- プロンプトに要約の長さの指示が含まれる
- プロンプトに日本語で出力する指示が含まれる
- プロンプトに文体の指示が含まれる

### 5.4 エラーハンドリング

- [x] `Aws::BedrockRuntime::Errors::ServiceError` をキャッチする
- [x] エラー時にログを出力し nil を返す処理を実装する
- [x] エラー内容をRailsロガーで記録する

**受け入れ基準:**
- Bedrock API エラー時に例外が伝播せず nil が返る
- エラー内容がログに記録される
- サービス障害時もアプリケーションが停止しない

---

## 6. BookmarkCreatorService の実装

### 6.1 基本構造の作成

- [x] `app/services/bookmark_creator_service.rb` を作成する
- [x] Result 構造体（success?, bookmark, error, status）を定義する
- [x] コンストラクタでURLを受け取る設計にする

**受け入れ基準:**
- サービスオブジェクトとしてインスタンス化できる
- `call` メソッドで Result を返す

### 6.2 バリデーションと重複チェック

- [x] URL形式のバリデーション処理を実装する（HTTP/HTTPS のみ許可）
- [x] URL正規化処理を実装する（末尾スラッシュ、フラグメント除去）
- [x] 正規化後のURLで重複チェックを行う処理を実装する
- [x] 不正URL時は422、重複時は409を返す

**受け入れ基準:**
- 無効なURL形式で422エラーが返る
- 既に登録済みのURLで409エラーが返る
- URL正規化後の値で重複判定が行われる

### 6.3 オーケストレーション処理

- [x] WebFetcherService を呼び出してページ情報を取得する
- [x] ページ取得成功時のみ SummarizerService を呼び出す
- [x] 取得結果をデータベースに保存する
- [x] ページ取得失敗時はタイトル・要約を空文字で登録する
- [x] 要約生成失敗時は要約を空文字で登録する

**受け入れ基準:**
- 正常系: URL、タイトル、要約が保存される
- ページ取得失敗時: URLのみ保存され、タイトル・要約は空
- 要約生成失敗時: URL、タイトルが保存され、要約は空
- すべてのケースで201レスポンスが返る

---

## 7. APIキー認証の実装

### 7.1 認証Concernの作成

- [x] `app/controllers/concerns/api_key_authenticatable.rb` を作成する
- [x] `X-API-Key` ヘッダーからAPIキーを取得する処理を実装する
- [x] 環境変数 `API_KEY` との照合処理を実装する
- [x] `ActiveSupport::SecurityUtils.secure_compare` でタイミング攻撃対策を行う
- [x] 認証失敗時に401 Unauthorized を返す

**受け入れ基準:**
- 正しいAPIキーでリクエストが通る
- APIキーが未指定の場合401が返る
- APIキーが不正な場合401が返る
- タイミング攻撃に対して安全である

### 7.2 ApplicationController への適用

- [x] `ApplicationController` に認証Concernを include する
- [x] ヘルスチェックエンドポイントは認証をスキップする設定を行う

**受け入れ基準:**
- `/api/v1/bookmarks` へのリクエストに認証が必要である
- `/health` へのリクエストには認証が不要である

---

## 8. BookmarksController の実装

### 8.1 コントローラの基本構造

- [x] `app/controllers/api/v1/bookmarks_controller.rb` を作成する
- [x] 名前空間（Api::V1）を設定する
- [x] ApiKeyAuthenticatable を include する

**受け入れ基準:**
- コントローラが正しい名前空間に配置されている
- 認証が全アクションに適用されている

### 8.2 create アクション（ブックマーク登録）

- [x] リクエストボディから `url` パラメータを取得する
- [x] BookmarkCreatorService を呼び出す
- [x] 成功時は201とブックマーク情報をJSONで返す
- [x] 失敗時は適切なステータスコードとエラーメッセージを返す

**受け入れ基準:**
- `POST /api/v1/bookmarks` でブックマークが登録できる
- レスポンスに id, url, title, summary, created_at, updated_at が含まれる
- URLが不正な場合422が返る
- 重複URLの場合409が返る

### 8.3 index アクション（一覧取得）

- [x] ブックマークを作成日時の降順で取得する
- [x] Kaminari によるページネーション処理を実装する
- [x] デフォルト20件/ページの設定を行う
- [x] レスポンスにページネーションメタ情報を含める

**受け入れ基準:**
- `GET /api/v1/bookmarks` でブックマーク一覧が返る
- 新しい順（降順）でソートされている
- `page` パラメータでページを指定できる
- `per_page` パラメータで件数を指定できる
- meta にcurrent_page, total_pages, total_count, per_page が含まれる

### 8.4 show アクション（詳細取得）

- [x] パスパラメータの `id` からブックマークを取得する
- [x] ブックマーク情報をJSONで返す
- [x] 存在しないIDの場合404を返す

**受け入れ基準:**
- `GET /api/v1/bookmarks/:id` でブックマーク詳細が返る
- レスポンスに id, url, title, summary, created_at, updated_at が含まれる
- 存在しないIDで404が返る

### 8.5 destroy アクション（削除）

- [x] パスパラメータの `id` からブックマークを取得し削除する
- [x] 成功時は204 No Content を返す
- [x] 存在しないIDの場合404を返す

**受け入れ基準:**
- `DELETE /api/v1/bookmarks/:id` でブックマークが削除される
- 削除後にレスポンスボディがない（204）
- 存在しないIDで404が返る
- 削除後に同じIDで取得すると404になる

### 8.6 search アクション（検索）

- [x] クエリパラメータ `q` でキーワードを受け取る
- [x] Bookmark.search スコープを利用して検索する
- [x] 結果を作成日時の降順でソートする
- [x] ページネーション処理を実装する

**受け入れ基準:**
- `GET /api/v1/bookmarks/search?q=keyword` で検索結果が返る
- タイトルに含まれるキーワードで検索できる
- 要約に含まれるキーワードで検索できる
- 検索結果にページネーションメタ情報が含まれる
- キーワードが空の場合は空の結果が返る

### 8.7 ルーティングの設定

- [x] `config/routes.rb` に API v1 の名前空間を設定する
- [x] bookmarks リソース（create, index, show, destroy）を定義する
- [x] search コレクションルートを追加する
- [x] ヘルスチェックルート（`/health`）を追加する

**受け入れ基準:**
- `rails routes` で全エンドポイントが正しく表示される
- 各エンドポイントが期待するHTTPメソッドとパスに対応している

---

## 9. Rack::Attack（レートリミット）の設定

### 9.1 設定ファイルの作成

- [ ] `config/initializers/rack_attack.rb` を作成する
- [ ] `/api/` パスへのリクエストに対してIPベースのスロットリングを設定する
- [ ] 制限値を環境変数 `RATE_LIMIT_PER_MINUTE` から取得する（デフォルト10）
- [ ] 制限期間を1分に設定する

**受け入れ基準:**
- 1分間に10リクエストを超えるとスロットリングされる
- 環境変数で制限値を変更できる
- `/health` エンドポイントはレートリミットの対象外である

### 9.2 レートリミット超過時のレスポンス

- [ ] 超過時に429ステータスコードを返す設定を行う
- [ ] JSON形式のエラーレスポンスを返す
- [ ] エラーコード `rate_limit_exceeded` とメッセージを含める

**受け入れ基準:**
- レートリミット超過時に429が返る
- レスポンスが統一エラー形式のJSONである
- Content-Type が `application/json` である

---

## 10. エラーハンドリングの共通化

### 10.1 ApplicationController のエラーハンドリング

- [ ] `ActiveRecord::RecordNotFound` を rescue して404を返す
- [ ] `ActionController::ParameterMissing` を rescue して400を返す
- [ ] 予期しない例外を rescue して500を返す
- [ ] 全エラーレスポンスを統一JSON形式（error.code, error.message）にする

**受け入れ基準:**
- 存在しないリソースへのアクセスで統一形式の404エラーが返る
- 必須パラメータ欠落で統一形式の400エラーが返る
- 予期しないエラーで統一形式の500エラーが返る
- エラーレスポンスに `code` と `message` が含まれる

### 10.2 ログ出力の設定

- [ ] リクエスト/レスポンスのログ出力を確認する
- [ ] エラー発生時のスタックトレースをログに出力する
- [ ] 外部API呼び出しのログ出力を実装する（Bedrock、Webページ取得）
- [ ] ログレベルを環境変数 `RAILS_LOG_LEVEL` で制御する

**受け入れ基準:**
- リクエストの情報がログに記録される
- エラー時にスタックトレースがログに記録される
- Bedrock API 呼び出しの成否がログに記録される
- Webページ取得の成否がログに記録される

---

## 11. ヘルスチェックエンドポイント

### 11.1 ヘルスチェックの実装

- [ ] `GET /health` エンドポイントを実装する
- [ ] ステータス200と `{"status":"ok"}` を返す
- [ ] 認証をスキップする設定を行う
- [ ] レートリミットの対象外にする

**受け入れ基準:**
- `GET /health` で200と `{"status":"ok"}` が返る
- APIキーなしでアクセスできる
- レートリミットに影響されない

---

## 12. Minitest テストの実装

### 12.1 モデルテスト

- [ ] `test/models/bookmark_test.rb` を作成する
- [ ] バリデーションのテスト（presence, uniqueness, format）を記述する
- [ ] URL正規化のテストを記述する
- [ ] 検索スコープのテストを記述する
- [ ] フィクスチャ（`test/fixtures/bookmarks.yml`）を作成する

**受け入れ基準:**
- 全バリデーションがテストされている
- URL正規化の各パターンがテストされている
- 検索スコープが正しく動作することがテストされている
- テストが全て通る

### 12.2 WebFetcherService テスト

- [ ] `test/services/web_fetcher_service_test.rb` を作成する
- [ ] WebMock を使用してHTTPリクエストをスタブする
- [ ] 正常系（ページ取得成功）のテストを記述する
- [ ] リダイレクト追従のテストを記述する
- [ ] タイムアウト時のテストを記述する
- [ ] SSRF防止のテストを記述する
- [ ] HTML解析（タイトル抽出、本文抽出）のテストを記述する

**受け入れ基準:**
- 外部通信なしでテストが実行できる（WebMock使用）
- 正常系・異常系の主要パターンがカバーされている
- テストが全て通る

### 12.3 SummarizerService テスト

- [ ] `test/services/summarizer_service_test.rb` を作成する
- [ ] Bedrock API呼び出しをモック/スタブする
- [ ] 正常系（要約取得成功）のテストを記述する
- [ ] エラー系（API失敗で nil を返す）のテストを記述する
- [ ] テキスト切り詰め処理のテストを記述する

**受け入れ基準:**
- Bedrock APIへの実際の通信なしでテストが実行できる
- 正常系・異常系がカバーされている
- テストが全て通る

### 12.4 BookmarkCreatorService テスト

- [ ] `test/services/bookmark_creator_service_test.rb` を作成する
- [ ] WebFetcherService と SummarizerService をスタブする
- [ ] 正常系（全処理成功）のテストを記述する
- [ ] URL不正時のテストを記述する
- [ ] URL重複時のテストを記述する
- [ ] ページ取得失敗時（タイトル・要約が空で登録）のテストを記述する
- [ ] 要約生成失敗時（要約が空で登録）のテストを記述する

**受け入れ基準:**
- オーケストレーション処理の全パターンがテストされている
- 外部サービスへの依存なしでテストが実行できる
- テストが全て通る

### 12.5 コントローラテスト（BookmarksController）

- [ ] `test/controllers/api/v1/bookmarks_controller_test.rb` を作成する
- [ ] 認証のテスト（正常認証、認証なし、不正キー）を記述する
- [ ] POST /api/v1/bookmarks のテスト（正常系、エラー系）を記述する
- [ ] GET /api/v1/bookmarks のテスト（一覧取得、ページネーション）を記述する
- [ ] GET /api/v1/bookmarks/:id のテスト（正常系、404）を記述する
- [ ] DELETE /api/v1/bookmarks/:id のテスト（正常系、404）を記述する
- [ ] GET /api/v1/bookmarks/search のテスト（正常系、結果なし）を記述する

**受け入れ基準:**
- 全エンドポイントの正常系・異常系がテストされている
- 認証処理がテストされている
- レスポンス形式（JSONの構造）が検証されている
- テストが全て通る

### 12.6 ヘルスチェックのテスト

- [ ] `test/integration/health_test.rb` を作成する
- [ ] 200レスポンスのテストを記述する
- [ ] 認証不要であることのテストを記述する

**受け入れ基準:**
- ヘルスチェックが認証なしで200を返すことがテストされている
- テストが全て通る

### 12.7 RuboCop の設定と実行

- [ ] `.rubocop.yml` を作成し、プロジェクトに合った設定を行う
- [ ] `bundle exec rubocop` を実行して警告を確認する
- [ ] 重大な警告を修正する

**受け入れ基準:**
- RuboCop がエラーなく実行できる
- 重大な警告（Error, Fatal）がない状態である
