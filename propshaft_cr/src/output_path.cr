# Порт Propshaft::OutputPath (lib/propshaft/output_path.rb, propshaft 1.3.2).

class Propshaft::OutputPath
  getter path : String
  getter manifest : Propshaft::Manifest

  def initialize(@path : String, @manifest : Propshaft::Manifest)
  end

  # clean(count, age): группируем по logical path, сортируем по mtime
  # (новые сначала), удаляем устаревшие за пределами age/count.
  #
  # 1:1 с гемом, включая его особенность: reject-условие
  # `path == current` сравнивает String с ManifestEntry и никогда не
  # истинно — текущая по манифесту версия не исключается из списка, а
  # защищается свежестью mtime/позицией в сортировке (она только что
  # записана process'ом).
  def clean(count : Int32, age : Time::Span) : Nil
    files.group_by(&.[:logical_path]).each do |_logical_path, versions|
      removing = false
      versions
        .sort_by(&.[:mtime])
        .reverse
        .each_with_index do |f, index|
          # drop_while гема: пока свежая (age) или в пределах count —
          # оставляем; после первого устаревшего удаляем и остальные.
          removing ||= !fresh_version_within_limit(f[:mtime], count,
            expires_at: age, limit: index)
          remove(f[:path]) if removing
        end
    end
  end

  private def files : Array(NamedTuple(path: String, logical_path: String, digest: String?, mtime: Time))
    list = [] of NamedTuple(path: String, logical_path: String, digest: String?, mtime: Time)
    all_files_from_tree(@path).each do |file|
      digested = file[(@path.size + 1)..]
      logical, digest = Propshaft::Asset.extract_path_and_digest(digested)
      list << {path: digested, logical_path: logical, digest: digest,
               mtime: File.info(file).modification_time}
    end
    list
  end

  private def fresh_version_within_limit(mtime : Time, count : Int32,
                                         expires_at : Time::Span, limit : Int32) : Bool
    modified_at = Math.max(0, (Time.utc - mtime).total_seconds)
    modified_at < expires_at.total_seconds || limit < count
  end

  private def remove(path : String) : Nil
    FileUtils.rm(File.join(@path, path))
    Propshaft.logger << "Removed #{path}\n"
  end

  private def all_files_from_tree(path : String) : Array(String)
    files = [] of String
    Dir.children(path).each do |child|
      full = File.join(path, child)
      if Dir.exists?(full)
        files.concat(all_files_from_tree(full))
      else
        files << full
      end
    end
    files
  end
end
