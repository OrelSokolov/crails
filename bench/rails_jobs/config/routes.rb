Rails.application.routes.draw do
  post "/enqueue", to: "bench#enqueue"
  get "/drain", to: "bench#drain"
  get "/reset", to: "bench#reset"
  get "/health", to: "bench#health"
  root to: proc { [200, {}, ["rails_jobs"]] }
end
