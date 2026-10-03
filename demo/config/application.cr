# NOTE: DEMO_CABLE / ChatChannel are required from src/app.cr ("./cable")
# before this file, so Application#call can reference them.
class Application < CRails::Application
  # Mount the ActionCable endpoint: Rails' `mount ActionCable.server => "/cable"`.
  def call(context : HTTP::Server::Context) : Nil
    case context.request.path
    when "/cable"          then DEMO_CABLE.ws_handler.call(context)
    when "/live/websocket" then DEMO_LIVE.call(context)
    else
      super
    end
  end
end

CRails.application = Application.new
