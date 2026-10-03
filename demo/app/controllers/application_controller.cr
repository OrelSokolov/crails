abstract class ApplicationController < ActionController::Base
  compile_partials({
    "note" => {path: "app/views/notes/_note.html.erb", locals: {"note" => Note}},
  })

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  def render_not_found(ex : Exception) : Nil
    render(plain: "Not Found", status: :not_found)
  end

  # Rails: render :new, status: :unprocessable_entity — renders another
  # action's template (action_pack's implicit render only knows the
  # current action).
  def render_action(action : String, status : Int32) : Nil
    response.status_code = status
    __default_render(action)
  end
end
