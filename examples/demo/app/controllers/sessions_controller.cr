class SessionsController < ApplicationController
  @email : String = ""

  def new
    redirect_to("/profile") if user_signed_in?
    @email = ""
  end

  def create
    email = params["email"].to_s.strip
    password = params["password"].to_s
    user = User.where("LOWER(email) = LOWER(?)", email).first?
    if user && user.valid_password?(password)
      sign_in(user)
      redirect_to("/profile", notice: "Signed in successfully.")
    else
      flash.now("alert", "Неверный email или пароль")
      @email = email
      render_action("new", 422)
    end
  end

  def destroy
    sign_out
    redirect_to("/", notice: "Signed out successfully.")
  end
end
