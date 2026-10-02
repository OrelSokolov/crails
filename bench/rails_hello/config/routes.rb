Rails.application.routes.draw do
  root "welcome#index"
  get "/posts", to: "posts#index"
  get "/posts/:id", to: "posts#show"
  post "/posts", to: "posts#create"
end
