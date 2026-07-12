# frozen_string_literal: true

require 'test_helper'

class BookmarkTest < ActiveSupport::TestCase
  # --- Validation: presence ---

  test 'valid bookmark with all attributes' do
    bookmark = Bookmark.new(url: 'https://example.org/valid', title: 'Valid', summary: 'Summary')

    assert_predicate bookmark, :valid?
  end

  test 'invalid without url' do
    bookmark = Bookmark.new(url: nil)

    assert_not bookmark.valid?
    assert_includes bookmark.errors[:url], "can't be blank"
  end

  # --- Validation: uniqueness ---

  test 'invalid with duplicate url' do
    bookmark = Bookmark.new(url: bookmarks(:one).url)

    assert_not bookmark.valid?
    assert_includes bookmark.errors[:url], 'has already been taken'
  end

  # --- Validation: format ---

  test 'valid with http url' do
    bookmark = Bookmark.new(url: 'http://example.org/page')

    assert_predicate bookmark, :valid?
  end

  test 'valid with https url' do
    bookmark = Bookmark.new(url: 'https://example.org/page')

    assert_predicate bookmark, :valid?
  end

  test 'invalid with ftp url' do
    bookmark = Bookmark.new(url: 'ftp://example.org/file')

    assert_not bookmark.valid?
    assert_includes bookmark.errors[:url], 'はHTTPまたはHTTPS形式である必要があります'
  end

  test 'invalid with javascript url' do
    bookmark = Bookmark.new(url: 'javascript:alert(1)')

    assert_not bookmark.valid?
  end

  # --- URL normalization ---

  test 'removes trailing slash' do
    bookmark = Bookmark.new(url: 'https://example.org/page/')
    bookmark.valid?

    assert_equal 'https://example.org/page', bookmark.url
  end

  test 'removes fragment' do
    bookmark = Bookmark.new(url: 'https://example.org/page#section')
    bookmark.valid?

    assert_equal 'https://example.org/page', bookmark.url
  end

  test 'removes fragment and trailing slash' do
    bookmark = Bookmark.new(url: 'https://example.org/page/#section')
    bookmark.valid?

    assert_equal 'https://example.org/page', bookmark.url
  end

  test 'strips whitespace' do
    bookmark = Bookmark.new(url: '  https://example.org/page  ')
    bookmark.valid?

    assert_equal 'https://example.org/page', bookmark.url
  end

  # --- Search scope ---

  test 'search finds bookmarks by title' do
    results = Bookmark.search('サンプル記事1')

    assert_includes results, bookmarks(:one)
    assert_not_includes results, bookmarks(:two)
  end

  test 'search finds bookmarks by summary' do
    results = Bookmark.search('検索テスト')

    assert_includes results, bookmarks(:two)
    assert_not_includes results, bookmarks(:one)
  end

  test 'search returns none for blank query' do
    results = Bookmark.search('')

    assert_empty results
  end

  test 'search returns none for nil query' do
    results = Bookmark.search(nil)

    assert_empty results
  end

  test 'search is case insensitive partial match' do
    results = Bookmark.search('サンプル')

    assert_includes results, bookmarks(:one)
    assert_includes results, bookmarks(:two)
  end

  test 'search handles special SQL characters safely' do
    results = Bookmark.search('100%')

    assert_empty results
  end
end
