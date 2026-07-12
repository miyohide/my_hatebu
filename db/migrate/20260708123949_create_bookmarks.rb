class CreateBookmarks < ActiveRecord::Migration[8.1]
  def change
    create_table :bookmarks do |t|
      t.text :url, null: false
      t.text :title, default: ''
      t.text :summary, default: ''
      t.timestamps
    end

    add_index :bookmarks, :url, unique: true
    add_index :bookmarks, :created_at, order: { created_at: :desc }
  end
end
