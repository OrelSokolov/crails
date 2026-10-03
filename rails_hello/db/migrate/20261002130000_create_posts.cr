class CreatePosts < ActiveRecord::Migration
  def change
    create_table :posts do |t|
      t.string :title, null: false
      t.text :body
      t.integer :views, default: 0_i64, null: false
      t.timestamps
    end
  end
end
