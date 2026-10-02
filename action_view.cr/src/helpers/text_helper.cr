# TextHelper + NumberHelper re-export — byte-exact with actionview
# 8.1.4 (oracle: txt_*, num_* cases). Number formatting delegates to
# ActiveSupport::NumberHelper (ported in Iteration 1, same methods
# Rails re-exports through ActionView).

module ActionView
  module Helpers
    module TextHelper
      def pluralize(count : Int, word : String) : String
        "#{count} #{count == 1 ? word : word.pluralize}"
      end

      def truncate(text : String, length : Int = 30, omission : String = "...",
                  separator : String? = nil, escape : Bool = true) : String
        return text if text.size <= length
        stop = length - omission.size
        stop = __av_rindex_at_most(text, separator, stop) || stop if separator
        result = "#{text[0, stop]}#{omission}"
        escape ? HTML.escape(result) : result
      end

      # Ruby's rindex(sep, limit): last occurrence starting at or before limit.
      private def __av_rindex_at_most(text : String, sep : String, limit : Int) : Int32?
        best = nil
        i = 0
        while idx = text.index(sep, i)
          break if idx > limit
          best = idx
          i = idx + 1
        end
        best
      end

      def excerpt(text : String, phrase : String, radius : Int = 100,
                  omission : String = "...") : String?
        return nil unless found = text.index(phrase)
        start_pos = {found - radius, 0}.max
        end_pos = {found + phrase.size + radius, text.size}.min
        prefix = start_pos == 0 ? "" : omission
        suffix = end_pos == text.size ? "" : omission
        "#{prefix}#{text[start_pos, end_pos - start_pos]}#{suffix}"
      end

      def highlight(text : String, phrases : String | Array(String),
                    highlighter : String = "<mark>\\1</mark>") : String
        list = phrases.is_a?(String) ? [phrases] : phrases
        return text if text.blank?
        pattern = list.map { |p| Regex.escape(p) }.join("|")
        text.gsub(/(#{pattern})/i) { |m| "<mark>#{m}</mark>" }
      end

      def word_wrap(text : String, line_width : Int = 80) : String
        text.split("\n").map do |line|
          lines = [] of String
          current = [] of String
          line.split(" ").each do |word|
            if current.empty? || current.join(" ").size + 1 + word.size <= line_width
              current << word
            else
              lines << current.join(" ")
              current = [word]
            end
          end
          lines << current.join(" ") unless current.empty?
          lines.join("\n")
        end.join("\n")
      end

      def simple_format(text : String) : String
        text.split(/\n{2,}/).map { |para|
          "<p>#{para.gsub(/\n/, "\n<br />")}</p>"
        }.join("\n\n")
      end

      # --- cycle ---------------------------------------------------
      @__av_cycle_values = {} of String => Array(String)
      @__av_cycle_current = {} of String => Int32
      @__av_cycle_last : String? = nil

      def cycle(*values : String) : String
        key = values.join("-")
        @__av_cycle_values[key] = values.to_a unless @__av_cycle_values[key]?
        @__av_cycle_last = key
        current = @__av_cycle_current[key]? || 0
        @__av_cycle_current[key] = (current + 1) % @__av_cycle_values[key].size
        @__av_cycle_values[key][current]? || @__av_cycle_values[key][0]
      end

      def current_cycle : String?
        key = @__av_cycle_last
        return nil unless key && @__av_cycle_values[key]?
        current = @__av_cycle_current[key]? || 0
        idx = current == 0 ? @__av_cycle_values[key].size - 1 : current - 1
        @__av_cycle_values[key][idx]?
      end

      def reset_cycle : Nil
        key = @__av_cycle_last
        return unless key
        @__av_cycle_current[key] = 0
      end

      # --- distance_of_time_in_words (Rails algorithm) --------------
      def distance_of_time_in_words(from_time : Time, to_time : Time,
                                     include_seconds : Bool = false) : String
        seconds = (to_time - from_time).total_seconds.abs
        minutes = (seconds / 60).round.to_i

        if minutes <= 1
          return minutes == 0 ? "less than a minute" : "1 minute" unless include_seconds
          case seconds.round.to_i
          when 0..4   then "less than 5 seconds"
          when 5..9   then "less than 10 seconds"
          when 10..19 then "less than 20 seconds"
          when 20..39 then "half a minute"
          when 40..59 then "less than a minute"
          else             "1 minute"
          end
        elsif minutes <= 44
          "#{minutes} minutes"
        elsif minutes <= 89
          "about 1 hour"
        elsif minutes <= 1439
          "about #{(minutes / 60.0).round.to_i} hours"
        elsif minutes <= 2519
          "about 1 day"
        elsif minutes <= 43199
          "#{(minutes / 1440.0).round.to_i} days"
        elsif minutes <= 86399
          "about 1 month"
        elsif minutes <= 525599
          "#{(minutes / 43200.0).round.to_i} months"
        else
          years = (minutes / 525600.0).round.to_i
          remainder = ((minutes / 43200.0).round.to_i % 12)
          if remainder.zero?
            "#{years} #{years == 1 ? "year" : "years"}"
          elsif years == 1
            "about 1 year"
          else
            "over #{years} years"
          end
        end
      end
    end

    module NumberHelper
      include ActiveSupport::NumberHelper

      def number_to_currency(number : Int | Float, **options) : String
        ActiveSupport::NumberHelper.number_to_currency(number, **options)
      end

      def number_with_delimiter(number : Int | Float, **options) : String
        ActiveSupport::NumberHelper.number_with_delimited(number, **options)
      end

      def number_with_precision(number : Int | Float, **options) : String
        ActiveSupport::NumberHelper.number_with_precision(number, **options)
      end

      def number_to_percentage(number : Int | Float, **options) : String
        ActiveSupport::NumberHelper.number_to_percentage(number, **options)
      end

      def number_to_human_size(number : Int | Float, **options) : String
        ActiveSupport::NumberHelper.number_to_human_size(number, **options)
      end

      def number_to_human(number : Int | Float, **options) : String
        ActiveSupport::NumberHelper.number_to_human(number, **options)
      end

      def number_to_phone(number : Int | String, **options) : String
        ActiveSupport::NumberHelper.number_to_phone(number, **options)
      end
    end
  end
end
