# /cable — ActionCable-совместимый WS-эндпоинт с ботом-калькулятором.
# Монтируется в Application#call (config/application.cr): путь /cable
# уходит в ws_handler, остальное — обычный HTTP-стек.

require "action_cable_cr"
require "json"

# Бот: считает квадрат числа. perform_action диспатчит по data["action"],
# поэтому публичный метод #square и становится RPC-эндпоинтом канала.
class ChatChannel < ActionCable::Channel::Base
  def subscribed : Nil
    reply("Hi! Send me a number and I will square it.")
  end

  # Порог «слишком большое»: выше квадрат уже не представим точно
  # (Int64 переполняется уже на 3.0e9²), отдаем ошибку, а не Infinity.
  MAX_INPUT = 1e15

  def square(data : Hash(String, String)) : Nil
    raw = data["number"]?.to_s.strip
    n = raw.to_f?
    if n.nil? || raw.empty?
      reply("“#{raw}” is not a number. Try, for example: 12 or 3.5")
    elsif n.abs > MAX_INPUT
      reply("“#{raw}” is too large — I square numbers up to 10¹⁵")
    else
      sq = n * n
      answer =
        if sq.floor == sq && sq.abs <= Int64::MAX.to_f64
          sq.floor.to_i64.to_s
        else
          sq.round(6).to_s
        end
      reply("#{fmt_in(raw)}² = #{answer}")
    end
  end

  # CableValue — рекурсивный алиас, литералы в него не инферятся:
  # тип указываем явно (включая ключ String | Symbol).
  private def reply(text : String) : Nil
    transmit({"from" => "bot", "text" => text} of String | Symbol => ActionCable::CableValue)
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
