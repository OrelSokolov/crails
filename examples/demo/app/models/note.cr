class Note < ActiveRecord::Base
  include Turbo::Broadcastable

  # Стрим "notes" (множественное имя модели): создание — prepend карточки
  # в сетку index (подписана через turbo_stream_from), просмотр заметки
  # инкрементит views и броадкастит replace карточки, удаление — remove.
  broadcasts inserts_by: :prepend, target: "notes"

  validates :title, presence: true, length: {maximum: 140}

  # Дефолты новых записей (БД-дефолта в схеме нет): цвет карточки и
  # стартовое значение счётчика просмотров.
  attribute :color, default: "sky"
  attribute :views, default: 0

  COLORS = {"amber", "rose", "sky", "emerald", "violet"}

  def snippet : String
    body = self.body.to_s
    stripped = body.gsub(/\s+/, " ").strip
    stripped.empty? ? "No description" : stripped.truncate(160)
  end

  def color_class : String
    COLORS.includes?(color.to_s) ? color.to_s : "sky"
  end
end
