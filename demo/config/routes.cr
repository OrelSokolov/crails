CRails.application.routes.draw do
  root "notes#index"
  get "/notes", to: "notes#index", as: "notes"
  get "/notes/new", to: "notes#new", as: "new_note"
  post "/notes", to: "notes#create"
  get "/notes/:id", to: "notes#show", as: "note"
  post "/notes/:id/destroy", to: "notes#destroy"

  get "/login", to: "sessions#new", as: "login"
  post "/login", to: "sessions#create"
  post "/logout", to: "sessions#destroy"

  get "/signup", to: "users#new", as: "signup"
  post "/signup", to: "users#create"
  get "/profile", to: "users#edit", as: "profile"
  post "/profile", to: "users#update"

  get "/chat", to: "chat#index", as: "chat"

  get "/live", to: "live#index", as: "live"
  get "/live_assets/:file", to: "live#asset"
end
