class PostsController < ApplicationController
  @posts : Array(Post) = [] of Post

  def index
    @posts = Post.order("id ASC").limit(20).to_a
  end

  def show
    post = Post.find(params["id"].to_s.to_i)
    render({id: post.id, title: post.title, views: post.views}.to_json)
  end

  def create
    post = Post.create({"title" => "bench-#{Time.utc.to_unix_ms}", "views" => 0_i64})
    if post.persisted?
      render({id: post.id}.to_json)
    else
      response.status_code = 422
      render({errors: post.errors.full_messages}.to_json, status: 422)
    end
  end
end
