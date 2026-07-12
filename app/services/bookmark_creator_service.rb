# frozen_string_literal: true

class BookmarkCreatorService
  Result = Struct.new(:success, :bookmark, :error, :status, keyword_init: true) do
    alias_method :success?, :success
  end

  def initialize(url)
    @url = url.to_s.strip
  end

  def call
    # 1. URL形式バリデーション
    return Result.new(success: false, bookmark: nil, error: 'URLが無効です', status: :unprocessable_entity) unless valid_url?

    # 2. URL正規化
    normalized = normalize_url(@url)

    # 3. 重複チェック
    return Result.new(success: false, bookmark: nil, error: 'このURLは既に登録されています', status: :conflict) if Bookmark.exists?(url: normalized)

    # 4. Webページ取得
    fetch_result = WebFetcherService.new(normalized).call

    # 5. AI要約生成（ページ取得成功時のみ）
    summary = nil
    summary = SummarizerService.new(fetch_result.body_text).call if fetch_result.success?

    # 6. データベース保存
    bookmark = Bookmark.create!(
      url: normalized,
      title: fetch_result.success? ? (fetch_result.title || '') : '',
      summary: summary || ''
    )

    Result.new(success: true, bookmark: bookmark, error: nil, status: :created)
  rescue ActiveRecord::RecordInvalid => e
    Result.new(success: false, bookmark: nil, error: e.message, status: :unprocessable_entity)
  end

  private

  def valid_url?
    uri = URI.parse(@url)
    uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
  rescue URI::InvalidURIError
    false
  end

  def normalize_url(url)
    uri = URI.parse(url)
    uri.fragment = nil
    uri.to_s.chomp('/')
  rescue URI::InvalidURIError
    url
  end
end
