class UsersController < ApplicationController
  @user : User? = nil

  def new
    redirect_to("/profile") if user_signed_in?
    @user = User.new
  end

  def create
    user = User.new
    user.name = params["name"].to_s.strip
    user.email = params["email"].to_s.strip
    user.password = params["password"].to_s
    user.password_confirmation = params["password_confirmation"].to_s
    if user.save
      sign_in(user)
      redirect_to("/profile", notice: "Добро пожаловать, #{user.name}!")
    else
      @user = user
      render_action("new", 422)
    end
  end

  def edit
    require_user
    @user = current_user
  end

  def update
    require_user
    user = current_user.not_nil!.as(User)
    ok = user.update_with_password({
      "current_password"    => params["current_password"].to_s,
      "name"                => params["name"].to_s.strip,
      "email"               => params["email"].to_s.strip,
      "password"            => params["password"].to_s,
      "password_confirmation" => params["password_confirmation"].to_s,
    })
    if ok
      redirect_to("/profile", notice: "Профиль обновлён")
    else
      @user = user
      render_action("edit", 422)
    end
  end
end
