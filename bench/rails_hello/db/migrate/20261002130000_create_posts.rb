# Same schema as the CRails app (bench/crails_ar/db/migrate/
# 20261002130000_create_posts.cr) — the benchmarks share one PG
# database (crails_bench), so this migration only matters for a
# fresh `bin/rails db:migrate` run.
class CreatePosts < ActiveRecord::Migration[8.1]
  def change
    create_table :posts do |t|
      t.string :title, null: false
      t.text :body
      t.integer :views, null: false, default: 0

      t.timestamps
    end
  end
end
