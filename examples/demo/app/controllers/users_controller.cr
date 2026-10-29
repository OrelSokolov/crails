class UsersController < ApplicationController
  @user : User? = nil

  before_action :authenticate_user!, only: [:edit, :update]
  before_action :redirect_if_signed_in, only: [:new, :create]

  # GET /signup
  def new
    @user = User.new
  end

  # POST /signup
  def create
    user = User.new
    user.name = sign_up_params["name"].to_s.strip
    user.email = sign_up_params["email"].to_s.strip
    user.password = sign_up_params["password"].to_s
    user.password_confirmation = sign_up_params["password_confirmation"].to_s
    if user.save
      devise_sign_in(user)
      redirect_to(profile_path, notice: "Welcome, #{user.name}!")
    else
      @user = user
      render_action("new", 422)
    end
  end

  # GET /profile
  def edit
    @user = current_user
  end

  # PATCH /profile — devise update_with_password (нужен текущий пароль)
  def update
    user = current_user.not_nil!
    if user.update_with_password({
      "current_password"      => account_params["current_password"].to_s,
      "name"                  => account_params["name"].to_s.strip,
      "email"                 => account_params["email"].to_s.strip,
      "password"              => account_params["password"].to_s,
      "password_confirmation" => account_params["password_confirmation"].to_s,
    })
      devise_sign_in(user) # salt сменился — обновляем warden-ключ сессии
      redirect_to(profile_path, notice: "Profile was successfully updated.")
    else
      @user = user
      render_action("edit", 422)
    end
  end

  private def redirect_if_signed_in : Nil
    redirect_to(profile_path) if user_signed_in?
  end

  private def sign_up_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation)
  end

  private def account_params
    params.require(:user).permit(:current_password, :name, :email,
      :password, :password_confirmation)
  end
end
