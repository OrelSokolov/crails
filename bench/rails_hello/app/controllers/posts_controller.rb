class PostsController < ApplicationController
  # Bench-only: CRails has no CSRF layer yet; this measures the AR
  # INSERT path, not forgery protection (see bench/results/101 notes).
  skip_before_action :verify_authenticity_token, only: :create

  def index
    @posts = Post.order(id: :asc).limit(20).to_a
  end

  def show
    post = Post.find(params[:id])
    render json: {id: post.id, title: post.title, views: post.views}
  end

  def create
    post = Post.create(title: "bench-#{Time.now.to_i * 1000}", views: 0)
    if post.persisted?
      render json: {id: post.id}
    else
      render json: {errors: post.errors.full_messages}, status: :unprocessable_entity
    end
  end
end
