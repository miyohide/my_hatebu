# frozen_string_literal: true

class BookmarksController < WebController
  # GET /bookmarks
  def index
    @bookmarks = Bookmark.order(created_at: :desc)
                         .page(params[:page])
                         .per(20)
  end

  # GET /bookmarks/:id
  def show
    @bookmark = Bookmark.find(params.expect(:id))
  end

  # GET /bookmarks/new
  def new; end

  # POST /bookmarks
  def create
    result = BookmarkCreatorService.new(params[:url]).call

    if result.success?
      redirect_to bookmark_path(result.bookmark), notice: 'ブックマークを登録した'
    else
      flash.now[:alert] = result.error
      render :new, status: :unprocessable_content
    end
  end

  # DELETE /bookmarks/:id
  def destroy
    bookmark = Bookmark.find(params.expect(:id))
    bookmark.destroy!
    redirect_to bookmarks_path, notice: 'ブックマークを削除した'
  end

  # GET /bookmarks/search
  def search
    @query = params[:q].to_s.strip
    @bookmarks = Bookmark.search(@query)
                         .order(created_at: :desc)
                         .page(params[:page])
                         .per(20)
  end
end
