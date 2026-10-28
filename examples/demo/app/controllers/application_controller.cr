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

  # --- session (action_pack cookie store) + devise.cr password check ----

  def current_user : User?
    if (id = session["user_id"])
      User.find?(id.to_i64)
    end
  end

  def user_signed_in? : Bool
    !current_user.nil?
  end

  def sign_in(user : User) : Nil
    session["user_id"] = user.id.to_s
  end

  def sign_out : Nil
    session.delete("user_id")
  end

  # authenticate_user! equivalent: gates profile pages.
  def require_user : Nil
    unless user_signed_in?
      flash["alert"] = "Нужно войти в аккаунт"
      redirect_to("/login")
    end
  end
end
