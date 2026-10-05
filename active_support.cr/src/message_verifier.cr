# ActiveSupport::MessageVerifier — подписанные значения, формат байт-в-байт
# с AS 8.1.4 (serializer: JSON, digest: SHA256):
#   Base64.strict_encode64(json) + "--" + Base64.strict_encode64(hmac_sha256)
# Оракул: turbo.cr/oracle/cases.rb (verifier_*, stream_name_*).

require "base64"
require "crypto/subtle"
require "openssl"

module ActiveSupport
  class MessageVerifier
    def initialize(@secret : String)
    end

    # Подписывает значение. Типы значений — те, что сериализует JSON в
    # AS: String / Array(String|Symbol) (символы едут строками).
    # Формат — как в AS 8.1.4: b64(json) + "--" + HEXdigest(HMAC-SHA256).
    def generate(value : String | Array(String | Symbol)) : String
      data = Base64.strict_encode(json_dump(value))
      "#{data}--#{OpenSSL::HMAC.hexdigest(:sha256, @secret, data)}"
    end

    # Возвращает исходную строку, если подпись верна; иначе nil.
    # (Для полезных нагрузок turbo это всегда String — имя стрима.)
    def verified(signed_message : String) : String?
      data, digest = signed_message.split("--", limit: 2)
      expected = OpenSSL::HMAC.hexdigest(:sha256, @secret, data)
      return nil unless Crypto::Subtle.constant_time_compare(expected, digest)
      json = Base64.decode_string(data)
      parsed = JSON.parse(json)
      parsed.as_s? ? parsed.as_s : nil
    rescue ArgumentError | Base64::Error | JSON::ParseException
      nil
    end

    private def json_dump(value : String | Array(String | Symbol)) : String
      if value.is_a?(String)
        value.to_json
      else
        String.build do |io|
          io << "["
          value.each_with_index do |v, i|
            io << "," if i > 0
            v.to_s.to_json(io)
          end
          io << "]"
        end
      end
    end
  end
end
