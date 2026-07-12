# frozen_string_literal: true

module Api
  module V1
    class BookmarksController < ApplicationController
      # GET /api/v1/bookmarks
      def index
        bookmarks = Bookmark.order(created_at: :desc)
                            .page(params[:page])
                            .per(params[:per_page] || 20)

        render json: {
          bookmarks: bookmarks.map { |b| bookmark_json(b) },
          meta: pagination_meta(bookmarks)
        }
      end

      # GET /api/v1/bookmarks/:id
      def show
        bookmark = Bookmark.find(params.expect(:id))
        render json: bookmark_json(bookmark)
      end

      # POST /api/v1/bookmarks
      def create
        result = BookmarkCreatorService.new(params[:url]).call

        if result.success?
          render json: bookmark_json(result.bookmark), status: :created
        else
          render json: { error: { code: error_code(result.status), message: result.error } }, status: result.status
        end
      end

      # DELETE /api/v1/bookmarks/:id
      def destroy
        bookmark = Bookmark.find(params.expect(:id))
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
          bookmarks: bookmarks.map { |b| bookmark_json(b) },
          meta: pagination_meta(bookmarks)
        }
      end

      private

      def bookmark_json(bookmark)
        {
          id: bookmark.id,
          url: bookmark.url,
          title: bookmark.title,
          summary: bookmark.summary,
          created_at: bookmark.created_at,
          updated_at: bookmark.updated_at
        }
      end

      def pagination_meta(collection)
        {
          current_page: collection.current_page,
          total_pages: collection.total_pages,
          total_count: collection.total_count,
          per_page: collection.limit_value
        }
      end

      def error_code(status)
        case status
        when :unprocessable_entity then 'invalid_url'
        when :conflict then 'duplicate_url'
        else 'error'
        end
      end
    end
  end
end
