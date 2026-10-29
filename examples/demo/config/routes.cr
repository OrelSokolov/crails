CRails.application.routes.draw do
  root "notes#index"

  devise_for :users   # /users/sign_in · DELETE /users/sign_out

  resources :notes, only: [:index, :new, :create, :show, :destroy]

  get "/signup", to: "users#new", as: "signup"
  post "/signup", to: "users#create"
  get "/profile", to: "users#edit", as: "profile"
  patch "/profile", to: "users#update"

  get "/chat", to: "chat#index", as: "chat"

  get "/live", to: "live#index", as: "live"
  get "/live_assets/:file", to: "live#asset"
end
