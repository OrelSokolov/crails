# Cookies / session / flash (cookie store).
#
# Deviation from Rails: the session and flash ride in their own
# (base64 JSON) cookies without signing/encryption yet — signed and
# encrypted cookie stores are Phase 2 work (action_pack.cr PLAN.md).
# Semantics match Rails: `flash[k] = v` shows on the NEXT request,
# `flash.now` on the current one, read once then discarded.

module ActionController
  class Cookies
    def initialize(@context : HTTP::Server::Context)
      @jar = {} of String => String
      request_cookies.each do |k, v|
        @jar[k] = v
      end
    end

    def [](name : String) : String?
      @jar[name]?
    end

    def []=(name : String, value : String) : Cookies
      @jar[name] = value
      write(name)
      self
    end

    def delete(name : String) : Nil
      @jar.delete(name)
      response = @context.response
      response.headers["Set-Cookie"] =
        "#{name}=; path=/; max-age=0; expires=Thu, 01 Jan 1970 00:00:00 GMT"
    end

    def has_key?(name : String) : Bool
      @jar.has_key?(name)
    end

    private def request_cookies : Hash(String, String)
      jar = {} of String => String
      header = @context.request.headers["Cookie"]?
      return jar unless header
      header.split(';').each do |part|
        key, value = part.split('=', 2)
        jar[key.strip] = value.try(&.strip) || ""
      end
      jar
    end

    private def write(name : String) : Nil
      @context.response.headers["Set-Cookie"] = "#{name}=#{URI.encode_www_form(@jar[name])}; path=/"
    end
  end

  class Session
    KEY = "crails_session"

    @data : Hash(String, String)

    def initialize(@cookies : Cookies)
      @data = @cookies[KEY].try { |raw| decode(raw) } || {} of String => String
    end

    def [](key : String | Symbol) : String?
      @data[key.to_s]?
    end

    def []?(key : String | Symbol) : String?
      @data[key.to_s]?
    end

    def []=(key : String | Symbol, value : String) : Nil
      @data[key.to_s] = value
      persist
    end

    def delete(key : String | Symbol) : Nil
      @data.delete(key.to_s)
      persist
    end

    def reset : Nil
      @data.clear
      persist
    end

    private def persist : Nil
      @cookies[KEY] = encode(@data)
    end

    private def decode(raw : String) : Hash(String, String)
      json = Base64.decode_string(raw)
      JSON.parse(json).as_h.each_with_object({} of String => String) do |(k, v), h|
        h[k] = v.to_s
      end
    rescue
      {} of String => String
    end

    private def encode(data : Hash(String, String)) : String
      Base64.strict_encode(data.to_json)
    end
  end

  class Flash
    KEY = "crails_flash"

    @current : Hash(String, String)
    @next : Hash(String, String) = {} of String => String

    def initialize(@cookies : Cookies)
      @current = @cookies[KEY].try { |raw| decode(raw) } || {} of String => String
      @cookies.delete(KEY) # flash is read once
    end

    # Written for the NEXT request (typical set-then-redirect).
    def []=(key : String | Symbol, value : String) : Nil
      @next[key.to_s] = value
      persist
    end

    # Read the flash carried over from the previous request.
    def [](key : String | Symbol) : String?
      @current[key.to_s]?
    end

    def []?(key : String | Symbol) : String?
      @current[key.to_s]?
    end

    # Shown on the CURRENT request only.
    def now(key : String | Symbol, value : String) : Nil
      @current[key.to_s] = value
    end

    def key?(key : String | Symbol) : Bool
      @current.has_key?(key.to_s)
    end

    def discard(key : String | Symbol) : Nil
      @current.delete(key.to_s)
    end

    def keep(key : String | Symbol) : Nil
      if v = @current[key.to_s]?
        @next[key.to_s] = v
        persist
      end
    end

    private def persist : Nil
      if @next.empty?
        @cookies.delete(KEY)
      else
        @cookies[KEY] = Base64.strict_encode(@next.to_json)
      end
    end

    private def decode(raw : String) : Hash(String, String)
      JSON.parse(Base64.decode_string(raw)).as_h.each_with_object({} of String => String) do |(k, v), h|
        h[k] = v.to_s
      end
    rescue
      {} of String => String
    end
  end
end
