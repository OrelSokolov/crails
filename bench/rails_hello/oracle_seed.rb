# Seed for the integration oracle: deterministic 3 posts, ids 1..3.
# Run inside the Rails app:  bin/rails runner oracle_seed.rb
Post.delete_all
ActiveRecord::Base.connection.execute(
  "DELETE FROM sqlite_sequence WHERE name = 'posts'")
Post.create!([
  {title: "first post", body: "hello world", views: 3},
  {title: "second post", body: nil, views: 0},
  {title: "third & <post>", body: nil, views: 42},
])
puts "seeded #{Post.count} posts"
