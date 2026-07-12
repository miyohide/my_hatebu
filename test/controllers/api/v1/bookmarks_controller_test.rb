# frozen_string_literal: true

require 'test_helper'

module Api
  module V1
    class BookmarksControllerTest < ActionDispatch::IntegrationTest
      # --- Authentication ---

      test 'returns 401 without api key' do
        get api_v1_bookmarks_url

        assert_response :unauthorized
        json = response.parsed_body

        assert_equal 'unauthorized', json.dig('error', 'code')
      end

      test 'returns 401 with invalid api key' do
        get api_v1_bookmarks_url, headers: { 'X-API-Key' => 'wrong_key' }

        assert_response :unauthorized
      end

      test 'returns 200 with valid api key' do
        get api_v1_bookmarks_url, headers: api_key_headers

        assert_response :success
      end

      # --- POST /api/v1/bookmarks ---

      test 'create returns 201 on success' do
        url = 'https://brand-new-site.com/page'
        fetch_result = WebFetcherService::Result.new(
          success: true, title: 'New Page', body_text: 'Body', error: nil
        )
        WebFetcherService.any_instance.stubs(:call).returns(fetch_result)
        SummarizerService.any_instance.stubs(:call).returns('要約テキスト')

        post api_v1_bookmarks_url,
             params: { url: url }.to_json,
             headers: authenticated_json_headers

        assert_response :created
        json = response.parsed_body

        assert_equal url, json['url']
        assert_equal 'New Page', json['title']
        assert_equal '要約テキスト', json['summary']
        assert json.key?('id')
        assert json.key?('created_at')
        assert json.key?('updated_at')
      end

      test 'create returns 422 for invalid url' do
        post api_v1_bookmarks_url,
             params: { url: 'not-a-valid-url' }.to_json,
             headers: authenticated_json_headers

        assert_response :unprocessable_entity
        json = response.parsed_body

        assert_equal 'invalid_url', json.dig('error', 'code')
      end

      test 'create returns 409 for duplicate url' do
        post api_v1_bookmarks_url,
             params: { url: bookmarks(:one).url }.to_json,
             headers: authenticated_json_headers

        assert_response :conflict
        json = response.parsed_body

        assert_equal 'duplicate_url', json.dig('error', 'code')
      end

      # --- GET /api/v1/bookmarks ---

      test 'index returns bookmarks in descending order' do
        get api_v1_bookmarks_url, headers: api_key_headers

        assert_response :success
        json = response.parsed_body

        assert json.key?('bookmarks')
        assert json.key?('meta')

        bookmarks_list = json['bookmarks']

        assert_operator bookmarks_list.length, :>, 0

        # Verify descending order by created_at
        dates = bookmarks_list.pluck('created_at')

        assert_equal dates, dates.sort.reverse
      end

      test 'index returns pagination meta' do
        get api_v1_bookmarks_url, headers: api_key_headers

        json = response.parsed_body
        meta = json['meta']

        assert meta.key?('current_page')
        assert meta.key?('total_pages')
        assert meta.key?('total_count')
        assert meta.key?('per_page')
      end

      test 'index respects per_page parameter' do
        get api_v1_bookmarks_url, params: { per_page: 1 }, headers: api_key_headers

        json = response.parsed_body

        assert_equal 1, json['bookmarks'].length
        assert_equal 1, json['meta']['per_page']
      end

      test 'index respects page parameter' do
        get api_v1_bookmarks_url, params: { per_page: 1, page: 2 }, headers: api_key_headers

        json = response.parsed_body

        assert_equal 2, json['meta']['current_page']
      end

      # --- GET /api/v1/bookmarks/:id ---

      test 'show returns bookmark details' do
        bookmark = bookmarks(:one)
        get api_v1_bookmark_url(bookmark), headers: api_key_headers

        assert_response :success
        json = response.parsed_body

        assert_equal bookmark.id, json['id']
        assert_equal bookmark.url, json['url']
        assert_equal bookmark.title, json['title']
        assert_equal bookmark.summary, json['summary']
        assert json.key?('created_at')
        assert json.key?('updated_at')
      end

      test 'show returns 404 for non-existent id' do
        get api_v1_bookmark_url(id: 999_999), headers: api_key_headers

        assert_response :not_found
        json = response.parsed_body

        assert_equal 'not_found', json.dig('error', 'code')
      end

      # --- DELETE /api/v1/bookmarks/:id ---

      test 'destroy deletes bookmark and returns 204' do
        bookmark = bookmarks(:one)
        assert_difference('Bookmark.count', -1) do
          delete api_v1_bookmark_url(bookmark), headers: api_key_headers
        end

        assert_response :no_content
        assert_empty response.body
      end

      test 'destroy returns 404 for non-existent id' do
        delete api_v1_bookmark_url(id: 999_999), headers: api_key_headers

        assert_response :not_found
        json = response.parsed_body

        assert_equal 'not_found', json.dig('error', 'code')
      end

      test 'destroy makes bookmark inaccessible' do
        bookmark = bookmarks(:one)
        delete api_v1_bookmark_url(bookmark), headers: api_key_headers

        assert_response :no_content

        get api_v1_bookmark_url(bookmark), headers: api_key_headers

        assert_response :not_found
      end

      # --- GET /api/v1/bookmarks/search ---

      test 'search returns matching bookmarks by title' do
        get search_api_v1_bookmarks_url, params: { q: 'サンプル記事1' }, headers: api_key_headers

        assert_response :success
        json = response.parsed_body

        assert_operator json['bookmarks'].length, :>, 0
        assert(json['bookmarks'].any? { |b| b['url'] == bookmarks(:one).url })
      end

      test 'search returns matching bookmarks by summary' do
        get search_api_v1_bookmarks_url, params: { q: '検索テスト' }, headers: api_key_headers

        assert_response :success
        json = response.parsed_body

        assert_operator json['bookmarks'].length, :>, 0
        assert(json['bookmarks'].any? { |b| b['url'] == bookmarks(:two).url })
      end

      test 'search returns empty for blank query' do
        get search_api_v1_bookmarks_url, params: { q: '' }, headers: api_key_headers

        assert_response :success
        json = response.parsed_body

        assert_empty json['bookmarks']
      end

      test 'search returns empty for no matches' do
        get search_api_v1_bookmarks_url, params: { q: '存在しないキーワード12345' }, headers: api_key_headers

        assert_response :success
        json = response.parsed_body

        assert_empty json['bookmarks']
      end

      test 'search includes pagination meta' do
        get search_api_v1_bookmarks_url, params: { q: 'サンプル' }, headers: api_key_headers

        json = response.parsed_body

        assert json.key?('meta')
        assert json['meta'].key?('current_page')
        assert json['meta'].key?('total_pages')
        assert json['meta'].key?('total_count')
        assert json['meta'].key?('per_page')
      end
    end
  end
end
