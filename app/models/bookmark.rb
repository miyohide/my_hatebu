class Bookmark < ApplicationRecord
  before_validation :normalize_url

  validates :url, presence: true,
                  uniqueness: true,
                  format: { with: /\Ahttps?:\/\/.+/i, message: "はHTTPまたはHTTPS形式である必要があります" }

  scope :search, ->(query) {
    return none if query.blank?

    keyword = "%#{sanitize_sql_like(query)}%"
    where("title LIKE :keyword OR summary LIKE :keyword", keyword: keyword)
  }

  private

  def normalize_url
    return if url.blank?

    self.url = url.strip
    uri = URI.parse(url)
    uri.fragment = nil
    self.url = uri.to_s
    self.url = url.chomp("/")
  rescue URI::InvalidURIError
    # Leave URL as-is if parsing fails; format validation will catch it
  end
end
