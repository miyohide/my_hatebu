# frozen_string_literal: true

require "net/http"
require "uri"
require "resolv"
require "ipaddr"
require "nokogiri"

class WebFetcherService
  Result = Struct.new(:success, :title, :body_text, :error, keyword_init: true) do
    alias_method :success?, :success
  end

  MAX_REDIRECTS = 5
  MAX_RETRIES = 2
  CONNECT_TIMEOUT = 10
  READ_TIMEOUT = 10
  USER_AGENT = "MyHatebuBot/1.0"
  MAX_BODY_LENGTH = 10_000

  BLOCKED_RANGES = [
    IPAddr.new("10.0.0.0/8"),
    IPAddr.new("172.16.0.0/12"),
    IPAddr.new("192.168.0.0/16"),
    IPAddr.new("127.0.0.0/8"),
    IPAddr.new("169.254.0.0/16"),
    IPAddr.new("0.0.0.0/8"),
    IPAddr.new("::1/128")
  ].freeze

  def initialize(url)
    @url = url
  end

  def call
    Rails.logger.info("WebFetcherService: Fetching URL: #{@url}")

    response_body = fetch_with_retry(@url)
    if response_body.is_a?(Result) && !response_body.success?
      Rails.logger.warn("WebFetcherService: Failed to fetch #{@url} - #{response_body.error}")
      return response_body
    end

    result = parse_html(response_body)
    Rails.logger.info("WebFetcherService: Successfully fetched #{@url} (title: #{result.title&.truncate(50)})")
    result
  rescue StandardError => e
    Rails.logger.error("WebFetcherService: Unexpected error fetching #{@url} - #{e.class}: #{e.message}")
    Result.new(success: false, title: nil, body_text: nil, error: e.message)
  end

  private

  def fetch_with_retry(url, retries: 0)
    fetch_page(url)
  rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
    if retries < MAX_RETRIES
      sleep(2**retries) # Exponential backoff: 1s, 2s
      fetch_with_retry(url, retries: retries + 1)
    else
      Result.new(success: false, title: nil, body_text: nil, error: "Timeout: #{e.message}")
    end
  rescue ServerError => e
    if retries < MAX_RETRIES
      sleep(2**retries)
      fetch_with_retry(url, retries: retries + 1)
    else
      Result.new(success: false, title: nil, body_text: nil, error: e.message)
    end
  end

  def fetch_page(url, redirect_count: 0)
    raise "Too many redirects" if redirect_count > MAX_REDIRECTS

    uri = URI.parse(url)
    validate_url!(uri)

    response = make_request(uri)

    case response
    when Net::HTTPRedirection
      location = response["location"]
      # Handle relative redirects
      location = URI.join(uri, location).to_s unless location.start_with?("http")
      fetch_page(location, redirect_count: redirect_count + 1)
    when Net::HTTPSuccess
      response.body
    when Net::HTTPClientError
      Result.new(success: false, title: nil, body_text: nil, error: "HTTP #{response.code}: #{response.message}")
    when Net::HTTPServerError
      raise ServerError, "Server error: #{response.code}"
    else
      Result.new(success: false, title: nil, body_text: nil, error: "HTTP #{response.code}: #{response.message}")
    end
  end

  def make_request(uri)
    # Resolve IP and validate before connecting
    ip_address = resolve_host(uri.host)
    validate_ip!(ip_address)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = CONNECT_TIMEOUT
    http.read_timeout = READ_TIMEOUT
    http.ipaddr = ip_address

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = USER_AGENT

    http.request(request)
  end

  def resolve_host(host)
    Resolv.getaddress(host)
  rescue Resolv::ResolvError
    raise "DNS resolution failed for #{host}"
  end

  def validate_url!(uri)
    raise "Invalid URL scheme" unless %w[http https].include?(uri.scheme)
    raise "Missing host" if uri.host.nil? || uri.host.empty?
  end

  def validate_ip!(ip)
    addr = IPAddr.new(ip)

    if BLOCKED_RANGES.any? { |range| range.include?(addr) }
      raise "Access to private/internal network is blocked: #{ip}"
    end
  end

  def parse_html(html_body)
    doc = Nokogiri::HTML(html_body)
    title = extract_title(doc)
    body_text = extract_body_text(doc)

    Result.new(success: true, title: title, body_text: body_text, error: nil)
  end

  def extract_title(doc)
    # Prefer og:title
    og_title = doc.at('meta[property="og:title"]')&.attr("content")
    return og_title.strip if og_title && !og_title.strip.empty?

    # Fallback to <title> tag
    title_tag = doc.at("title")&.text
    title_tag&.strip
  end

  def extract_body_text(doc)
    # Remove unwanted elements
    doc.css("script, style, nav, header, footer, noscript, iframe").remove

    # Get text content
    text = doc.at("body")&.text || ""

    # Normalize whitespace
    text = text.gsub(/[[:space:]]+/, " ").strip

    # Limit to MAX_BODY_LENGTH characters
    text[0, MAX_BODY_LENGTH] || ""
  end

  # Custom error class for 5xx server errors to enable retry logic
  class ServerError < StandardError; end
end
