require "test_helper"

class BookmarkTest < ActiveSupport::TestCase
  # Task 3.1: バリデーションのテスト

  test "有効なURLでブックマークを作成できる" do
    bookmark = Bookmark.new(url: "https://example.com/new-article")
    assert bookmark.valid?
  end

  test "URLが空の場合バリデーションエラーになる" do
    bookmark = Bookmark.new(url: "")
    assert_not bookmark.valid?
    assert_includes bookmark.errors[:url], "can't be blank"
  end

  test "URLがnilの場合バリデーションエラーになる" do
    bookmark = Bookmark.new(url: nil)
    assert_not bookmark.valid?
  end

  test "不正なURL形式の場合バリデーションエラーになる" do
    bookmark = Bookmark.new(url: "ftp://bad.com")
    assert_not bookmark.valid?
    assert_includes bookmark.errors[:url], "はHTTPまたはHTTPS形式である必要があります"
  end

  test "同じURLの重複登録ができない" do
    Bookmark.create!(url: "https://example.com/unique")
    duplicate = Bookmark.new(url: "https://example.com/unique")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:url], "has already been taken"
  end

  test "末尾スラッシュが正規化される" do
    bookmark = Bookmark.new(url: "https://example.com/path/")
    bookmark.valid?
    assert_equal "https://example.com/path", bookmark.url
  end

  test "フラグメントが正規化される" do
    bookmark = Bookmark.new(url: "https://example.com/page#section")
    bookmark.valid?
    assert_equal "https://example.com/page", bookmark.url
  end

  test "前後の空白がストリップされる" do
    bookmark = Bookmark.new(url: "  https://example.com/page  ")
    bookmark.valid?
    assert_equal "https://example.com/page", bookmark.url
  end

  test "HTTPのURLも有効" do
    bookmark = Bookmark.new(url: "http://example.com/page")
    assert bookmark.valid?
  end

  # Task 3.2: 検索スコープのテスト

  test "キーワードでタイトルを検索できる" do
    results = Bookmark.search("サンプル記事1")
    assert_includes results, bookmarks(:one)
  end

  test "キーワードで要約を検索できる" do
    results = Bookmark.search("検索テスト")
    assert_includes results, bookmarks(:two)
  end

  test "部分一致で検索結果が返る" do
    results = Bookmark.search("サンプル")
    assert_includes results, bookmarks(:one)
    assert_includes results, bookmarks(:two)
  end

  test "検索クエリが空の場合は結果が空になる" do
    results = Bookmark.search("")
    assert_empty results
  end

  test "検索クエリがnilの場合は結果が空になる" do
    results = Bookmark.search(nil)
    assert_empty results
  end

  test "一致する結果がない場合は空が返る" do
    results = Bookmark.search("存在しないキーワード12345")
    assert_empty results
  end
end
