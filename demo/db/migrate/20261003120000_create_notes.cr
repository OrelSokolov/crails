class CreateNotes < ActiveRecord::Migration
  def change
    create_table :notes do |t|
      t.string :title, null: false
      t.text :body
      t.string :color
      t.integer :views, default: 0_i64, null: false
      t.timestamps
    end
  end
end
