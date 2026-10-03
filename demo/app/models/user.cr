require "devise_cr"

class User < ActiveRecord::Base
  devise :database_authenticatable, :validatable

  def initials : String
    name.to_s.strip[0, 1].upcase
  end
end
