# Порт Propshaft::Asset (lib/propshaft/asset.rb, propshaft 1.3.2).

class Propshaft::Asset
  attr_reader path : String        # абсолютный путь на диске
  attr_reader logical_path : String
  attr_reader load_path : Propshaft::LoadPath

  # Минимальная Mime-таблица: content_type нужен только реестру
  # компиляторов (в Rails .mjs/.map не имеют Mime-типа → pass-through).
  CONTENT_TYPES = {
    ".css" => "text/css",
    ".js"  => "text/javascript",
  } of String => String

  def initialize(@path : String, @logical_path : String,
                 @load_path : Propshaft::LoadPath)
  end

  def compiled_content : String
    @compiled_content ||= @load_path.compilers.compile(self)
  end

  def content : String
    File.read(@path) # байты сохраняются (digest считается по bytes)
  end

  # Контент для regex-сканов: PCRE2 требует валидный UTF-8, а у
  # бинарных ассетов File.read даёт invalid-строку. Паттерны ASCII —
  # невалидные байты выбрасываются (invalid: :skip): ASCII-
  # подпоследовательность, а значит и совпадения, те же, что у
  # ruby-regex в ASCII-8BIT (отклонение закрыто: url в бинарнике
  # резолвится).
  def scannable_content : String
    @scannable_content ||= begin
      content = self.content
      content.valid_encoding? ? content : String.new(content.to_slice, "UTF-8", invalid: :skip)
    end
  end

  @scannable_content : String?

  def content_type : String?
    CONTENT_TYPES[File.extname(logical_path)]?
  end

  # SHA1(контент + контенты referenced + version), первые 8 hex.
  def digest : String
    @digest ||= Digest::SHA1.hexdigest(
      content_with_compile_references + (@load_path.version || "")
    )[0, 8]
  end

  # Subresource Integrity: sha256/sha384/sha512 от compiled_content.
  def integrity(hash_algorithm : String) : String
    case hash_algorithm
    when "sha256", "sha384", "sha512"
      # ok
    else
      raise Propshaft::Error.new(
        "Subresource Integrity hash algorithm must be one of SHA2 family (sha256, sha384, sha512)")
    end
    digest = OpenSSL::Digest.new(hash_algorithm)
    digest.update(compiled_content)
    "#{hash_algorithm}-#{Base64.strict_encode(String.new(digest.final))}"
  end

  def digested_path : String
    if already_digested?
      logical_path
    else
      # gsub-блок отдаёт совпавшую строку; группы — в $~.
      logical_path.sub(/\.(\w+(\.map)?)$/) { "-#{digest}#{$~.not_nil![0]}" }
    end
  end

  def fresh?(previous_digest : String?) : Bool
    digest == previous_digest || already_digested?
  end

  def ==(other : Propshaft::Asset) : Bool
    logical_path == other.logical_path
  end

  def hash : UInt64
    logical_path.hash
  end

  # Propshaft::Asset.extract_path_and_digest: digest — это
  # -[0-9a-zA-Z]{7,128} перед финальным расширением; вырезается первой
  # встречей в строке (sub, не только перед расширением).
  def self.extract_path_and_digest(digested_path : String) : {String, String?}
    if (match = digested_path.match(/-([0-9a-zA-Z]{7,128})\.(?!digested)([^.]|.map)+\z/)) &&
       (digest = match[1]?)
      {digested_path.sub("-#{digest}", ""), digest}
    else
      {digested_path, nil}
    end
  end

  private def content_with_compile_references : String
    content + @load_path.find_referenced_by(self).map(&.content).join
  end

  private def already_digested? : Bool
    logical_path.matches?(/-([0-9a-zA-Z_-]{7,128})\.digested/)
  end
end
