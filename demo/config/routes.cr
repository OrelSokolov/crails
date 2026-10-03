CRails.application.routes.draw do
  root "notes#index"
  get "/notes", to: "notes#index", as: "notes"
  get "/notes/new", to: "notes#new", as: "new_note"
  post "/notes", to: "notes#create"
  get "/notes/:id", to: "notes#show", as: "note"
  post "/notes/:id/destroy", to: "notes#destroy"
end
