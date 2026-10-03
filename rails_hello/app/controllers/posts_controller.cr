class PostsController < ApplicationController
  @posts : Array(Post) = [] of Post

  def index
    @posts = Post.order(id: :asc).limit(20).to_a
  end

  def show
    post = Post.find(params["id"].to_s.to_i64)
    render(json: {id: post.id, title: post.title, views: post.views}.to_json)
  end

  def create
    post = Post.create({"title" => "bench-#{Time.utc.to_unix_ms}", "views" => 0_i64})
    if post.persisted?
      render(json: {id: post.id}.to_json)
    else
      render(json: {errors: post.errors.full_messages}.to_json, status: :unprocessable_content)
    end
  end
end
