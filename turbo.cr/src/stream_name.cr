# Turbo::Streams::StreamName — подписанные имена стримов (1:1 с
# turbo-rails app/channels/turbo/streams/stream_name.rb).
#
# stream_name_from: записи → to_gid_param, строки/символы → to_s,
# массив склеивается через ":". Подпись — MessageVerifier (JSON,
# SHA256), байт-в-байт с AS 8.1.4 (оракул stream_name_*).

module Turbo
  module Streams
    module StreamName
      def self.stream_name_from(streamables : Array(Streamable)) : String
        streamables.map do |streamable|
          case streamable
          when ActiveRecord::Base then streamable.to_gid_param
          else                        streamable.to_s
          end
        end.join(":")
      end

      def self.signed_stream_name(streamables : Array(Streamable)) : String
        Turbo.signed_stream_verifier.generate(stream_name_from(streamables))
      end

      def self.verified_stream_name(signed_stream_name : String) : String?
        Turbo.signed_stream_verifier.verified(signed_stream_name)
      end
    end
  end
end
