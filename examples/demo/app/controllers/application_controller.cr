abstract class ApplicationController < ActionController::Base
  # Asset pipeline (propshaft): compute_asset_path во вьюхах резолвит
  # логические пути через манифест/load path.
  include CRails::PropshaftHelper

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

  # Типизированный current_user для контроллеров приложения: devise-хелперы
  # живут на ActionController::Base и возвращают ActiveRecord::Base+? (методов
  # модели там нет), а layout/вьюхи компилируются в контексте каждого
  # контроллера.
  def current_user : User?
    Devise.current(self).as?(User)
  end
end
