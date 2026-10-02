abstract class ApplicationController < ActionController::Base
  # Partials are compiled per app: the app knows its locals' types.
  compile_partials({
    "post" => {path: "app/views/posts/_post.html.erb", locals: {"post" => Post, "post_counter" => Int32}},
  })
end
