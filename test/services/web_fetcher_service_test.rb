# frozen_string_literal: true

require 'test_helper'

class WebFetcherServiceTest < ActiveSupport::TestCase
  setup do
    @url = 'https://example.com/article'
  end

  # --- Success case ---

  test 'fetches page and returns title and body text' do
    html = <<~HTML
      <html>
        <head><title>Test Page</title></head>
        <body><p>Hello World</p></body>
      </html>
    HTML
    stub_request(:get, @url).to_return(status: 200, body: html, headers: { 'Content-Type' => 'text/html' })

    result = WebFetcherService.new(@url).call

    assert_predicate result, :success?
    assert_equal 'Test Page', result.title
    assert_includes result.body_text, 'Hello World'
    assert_nil result.error
  end

  test 'extracts og:title when available' do
    html = <<~HTML
      <html>
        <head>
          <title>Fallback Title</title>
          <meta property="og:title" content="OG Title">
        </head>
        <body><p>Content</p></body>
      </html>
    HTML
    stub_request(:get, @url).to_return(status: 200, body: html)

    result = WebFetcherService.new(@url).call

    assert_predicate result, :success?
    assert_equal 'OG Title', result.title
  end

  test 'removes script and style tags from body text' do
    html = <<~HTML
      <html>
        <head><title>Page</title></head>
        <body>
          <script>alert('bad')</script>
          <style>.red { color: red; }</style>
          <p>Visible content</p>
        </body>
      </html>
    HTML
    stub_request(:get, @url).to_return(status: 200, body: html)

    result = WebFetcherService.new(@url).call

    assert_predicate result, :success?
    assert_includes result.body_text, 'Visible content'
    assert_not_includes result.body_text, 'alert'
    assert_not_includes result.body_text, '.red'
  end

  # --- Redirect ---

  test 'follows redirects' do
    stub_request(:get, @url).to_return(status: 302, headers: { 'Location' => 'https://example.com/redirected' })
    stub_request(:get, 'https://example.com/redirected')
      .to_return(status: 200, body: '<html><head><title>Redirected</title></head><body>OK</body></html>')

    result = WebFetcherService.new(@url).call

    assert_predicate result, :success?
    assert_equal 'Redirected', result.title
  end

  test 'fails after too many redirects' do
    6.times do |i|
      stub_request(:get, "https://example.com/redirect#{i}")
        .to_return(status: 302, headers: { 'Location' => "https://example.com/redirect#{i + 1}" })
    end

    result = WebFetcherService.new('https://example.com/redirect0').call

    assert_not result.success?
    assert_match(/Too many redirects/, result.error)
  end

  # --- Timeout ---

  test 'returns error on timeout' do
    stub_request(:get, @url).to_timeout

    result = WebFetcherService.new(@url).call

    assert_not result.success?
    assert_match(/Timeout|timeout|execution expired/i, result.error)
  end

  # --- SSRF Prevention ---

  test 'blocks private IP 10.x.x.x' do
    WebFetcherService.any_instance.stubs(:resolve_host).returns('10.0.0.1')

    result = WebFetcherService.new('https://private.example.com/secret').call

    assert_not result.success?
    assert_match(/private|blocked|internal/i, result.error)
  end

  test 'blocks loopback 127.x.x.x' do
    WebFetcherService.any_instance.stubs(:resolve_host).returns('127.0.0.1')

    result = WebFetcherService.new('https://localhost.example.com/secret').call

    assert_not result.success?
    assert_match(/private|blocked|internal/i, result.error)
  end

  test 'blocks link-local 169.254.x.x' do
    WebFetcherService.any_instance.stubs(:resolve_host).returns('169.254.1.1')

    result = WebFetcherService.new('https://link-local.example.com/metadata').call

    assert_not result.success?
    assert_match(/private|blocked|internal/i, result.error)
  end

  # --- Body text truncation ---

  test 'truncates body text to 10000 characters' do
    long_text = 'a' * 20_000
    html = "<html><head><title>Long</title></head><body><p>#{long_text}</p></body></html>"
    stub_request(:get, @url).to_return(status: 200, body: html)

    result = WebFetcherService.new(@url).call

    assert_predicate result, :success?
    assert_operator result.body_text.length, :<=, 10_000
  end

  # --- HTTP error responses ---

  test 'returns error for 404 without retry' do
    stub_request(:get, @url).to_return(status: 404)

    result = WebFetcherService.new(@url).call

    assert_not result.success?
    assert_match(/404/, result.error)
  end

  test 'retries on 500 server error' do
    stub_request(:get, @url)
      .to_return(status: 500)
      .then.to_return(status: 500)
      .then.to_return(status: 200, body: '<html><head><title>OK</title></head><body>Recovered</body></html>')

    result = WebFetcherService.new(@url).call

    assert_predicate result, :success?
    assert_equal 'OK', result.title
  end
end
