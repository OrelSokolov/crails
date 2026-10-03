abstract class ApplicationController < ActionController::Base
  # Partials are compiled per app: the app knows its locals' types.
  compile_partials({
    "post" => {path: "app/views/posts/_post.html.erb", locals: {"post" => Post, "post_counter" => Int32}},
  })

  # Rails maps ActiveRecord::RecordNotFound to a 404 automatically.
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  def render_not_found(ex : Exception) : Nil
    render(plain: "Not Found", status: :not_found)
  end
end
