# frozen_string_literal: true

require 'test_helper'

class BookmarkCreatorServiceTest < ActiveSupport::TestCase
  setup do
    @valid_url = 'https://new-example.com/article'
    @fetch_result_success = WebFetcherService::Result.new(
      success: true, title: '記事タイトル', body_text: '本文テキスト', error: nil
    )
    @fetch_result_failure = WebFetcherService::Result.new(
      success: false, title: nil, body_text: nil, error: 'Timeout'
    )
  end

  # --- Success case ---

  test 'creates bookmark with title and summary on full success' do
    WebFetcherService.any_instance.stubs(:call).returns(@fetch_result_success)
    SummarizerService.any_instance.stubs(:call).returns('生成された要約テキスト')

    result = BookmarkCreatorService.new(@valid_url).call

    assert_predicate result, :success?
    assert_equal @valid_url, result.bookmark.url
    assert_equal '記事タイトル', result.bookmark.title
    assert_equal '生成された要約テキスト', result.bookmark.summary
    assert_equal :created, result.status
  end

  # --- Invalid URL ---

  test 'returns error for invalid url' do
    result = BookmarkCreatorService.new('not-a-url').call

    assert_not result.success?
    assert_equal :unprocessable_entity, result.status
    assert_match(/無効/, result.error)
  end

  test 'returns error for ftp url' do
    result = BookmarkCreatorService.new('ftp://example.com/file').call

    assert_not result.success?
    assert_equal :unprocessable_entity, result.status
  end

  # --- Duplicate URL ---

  test 'returns error for duplicate url' do
    existing_url = bookmarks(:one).url

    result = BookmarkCreatorService.new(existing_url).call

    assert_not result.success?
    assert_equal :conflict, result.status
    assert_match(/既に登録/, result.error)
  end

  test 'detects duplicate after normalization' do
    # bookmarks(:one) has url "https://example.com/article-one"
    url_with_fragment = 'https://example.com/article-one#section'

    result = BookmarkCreatorService.new(url_with_fragment).call

    assert_not result.success?
    assert_equal :conflict, result.status
  end

  # --- Fetch failure ---

  test 'creates bookmark with empty title and summary when fetch fails' do
    WebFetcherService.any_instance.stubs(:call).returns(@fetch_result_failure)

    result = BookmarkCreatorService.new(@valid_url).call

    assert_predicate result, :success?
    assert_equal @valid_url, result.bookmark.url
    assert_equal '', result.bookmark.title
    assert_equal '', result.bookmark.summary
  end

  # --- Summary failure ---

  test 'creates bookmark with empty summary when summarizer fails' do
    WebFetcherService.any_instance.stubs(:call).returns(@fetch_result_success)
    SummarizerService.any_instance.stubs(:call).returns(nil)

    result = BookmarkCreatorService.new(@valid_url).call

    assert_predicate result, :success?
    assert_equal '記事タイトル', result.bookmark.title
    assert_equal '', result.bookmark.summary
  end

  # --- URL normalization ---

  test 'normalizes url before saving' do
    url_with_trailing_slash = 'https://new-example.com/page/'
    WebFetcherService.any_instance.stubs(:call).returns(@fetch_result_success)
    SummarizerService.any_instance.stubs(:call).returns('要約')

    result = BookmarkCreatorService.new(url_with_trailing_slash).call

    assert_predicate result, :success?
    assert_equal 'https://new-example.com/page', result.bookmark.url
  end
end
