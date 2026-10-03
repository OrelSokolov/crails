class Note < ActiveRecord::Base
  validates :title, presence: true, length: {maximum: 140}

  COLORS = {"amber", "rose", "sky", "emerald", "violet"}

  def snippet : String
    body = self.body.to_s
    stripped = body.gsub(/\s+/, " ").strip
    stripped.empty? ? "Без описания" : stripped.truncate(160)
  end

  def color_class : String
    COLORS.includes?(color.to_s) ? color.to_s : "sky"
  end
end
