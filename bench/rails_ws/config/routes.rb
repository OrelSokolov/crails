Rails.application.routes.draw do
  mount ActionCable.server => "/cable"
  post "/broadcast", to: "bench#broadcast"
  get "/health", to: "bench#health"
  root to: proc { [200, {}, ["rails_ws"]] }
end
