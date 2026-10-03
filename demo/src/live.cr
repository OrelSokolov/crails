# /live — LiveView-страница: счётчик (handle_event) и live-список заметок
# (ActiveRecord + форма phx-submit). Монтируется в Application#call
# (config/application.cr): путь /live/websocket уходит в ws-хендлер,
# остальное — обычный HTTP-стек.

require "live_view_cr"
require "random/secure"

# Счётчик: phx-click инкремент/декремент, handle_info тикает каждую секунду.
class DemoCounterLive < LiveView::Base
  @count : Int32 = 0
  @ticks : Int32 = 0

  def mount(params : Hash(String, JSON::Any), session : Hash(String, JSON::Any)) : Nil
    send_every(1.second, "tick")
  end

  def handle_event(event : String, params : JSON::Any) : Nil
    case event
    when "incr" then @count += 1
    when "decr" then @count -= 1
    end
  end

  def handle_info(message : LiveView::Info) : Nil
    case message
    when "tick" then @ticks += 1
    end
  end

  lv_template "app/views/live/counter_live.html"
end

# Live-список заметок: форма phx-submit создаёт Note, список обновляется.
class DemoNotesLive < LiveView::Base
  @titles : Array(String) = [] of String
  @last_created : String = ""

  def mount(params : Hash(String, JSON::Any), session : Hash(String, JSON::Any)) : Nil
    reload
  end

  def handle_event(event : String, params : JSON::Any) : Nil
    case event
    when "create"
      note = Note.new
      note.title = params.dig?("note", "title").try(&.as_s) || ""
      note.body = params.dig?("note", "body").try(&.as_s) || ""
      note.color = "sky"
      note.views = 0
      if note.save
        @last_created = note.title.to_s
        reload
      else
        @last_created = note.errors.full_messages.join(", ")
      end
    when "refresh"
      reload
    end
  end

  private def reload : Nil
    @titles = Note.order(id: :desc).limit(10).map(&.title.to_s)
  end

  lv_template "app/views/live/notes_live.html"
end

def new_live_id : String
  Random::Secure.hex(8)
end

DEMO_LIVE = LiveView::Socket.new(
  ENV.fetch("LIVE_VIEW_SECRET", "demo_live_view_secret"))
