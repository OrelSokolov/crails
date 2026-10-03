# /cable — ActionCable-совместимый WS-эндпоинт с ботом-калькулятором.
# Монтируется в Application#call (config/application.cr): путь /cable
# уходит в ws_handler, остальное — обычный HTTP-стек.

require "action_cable_cr"
require "json"

# Бот: считает квадрат числа. perform_action диспатчит по data["action"],
# поэтому публичный метод #square и становится RPC-эндпоинтом канала.
class ChatChannel < ActionCable::Channel::Base
  def subscribed : Nil
    reply("Привет! Напишите число — возведу его в квадрат.")
  end

  def square(data : Hash(String, String)) : Nil
    raw = data["number"]?.to_s.strip
    if raw.to_f? && !raw.empty?
      n = raw.to_f.not_nil!
      sq = n * n
      answer = sq.floor == sq ? sq.floor.to_i64.to_s : sq.round(6).to_s
      reply("#{fmt_in(raw)}² = #{answer}")
    else
      reply("«#{raw}» — не число. Попробуйте, например: 12 или 3.5")
    end
  end

  # CableValue is a recursive alias — hash literals don't infer into it,
  # so bot replies go through JSON::Any (which the alias includes).
  private def reply(text : String) : Nil
    transmit(JSON.parse({"from" => "bot", "text" => text}.to_json))
  end

  private def fmt_in(raw : String) : String
    if (i = raw.to_i64?)
      i.to_s
    else
      raw
    end
  end
end

DEMO_CABLE = ActionCable::Server.new
