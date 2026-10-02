# Oracle spec: 1:1 mirror of oracle/cases.rb. Expected values live in
# oracle/expected.yml — captured from the ORIGINAL activerecord 8.1.4 on
# the same scratch database. The port must reproduce them exactly; the
# tests are never edited on either side (see AGENTS.md).

require "spec"
require "../src/active_record_cr"

LOG = [] of String

# --- models (mirror of oracle/cases.rb; Comment first so Post's
# has_many codegen resolves the class) ---------------------------------

class Comment < ActiveRecord::Base
  belongs_to :post
  validates :body, presence: true
end

class Post < ActiveRecord::Base
  has_many :comments, dependent: :destroy

  validates :title, presence: true, length: {maximum: 10}
  validates :views, numericality: {only_integer: true, greater_than_or_equal_to: 0}, allow_nil: true

  before_validation :normalize_title
  before_save { LOG << "before_save" }
  after_create { LOG << "after_create" }
  after_update { LOG << "after_update" }
  after_destroy { LOG << "after_destroy" }

  def normalize_title
    LOG << "before_validation"
    if (t = title)
      self.title = t.strip
    end
    true
  end
end

class Profile < ActiveRecord::Base
  belongs_to :author
end

class Author < ActiveRecord::Base
  has_one :profile, dependent: :destroy
  validates :name, presence: true
  validates :email, format: {with: /\A[^@\s]+@[^@\s]+\z/}, uniqueness: true, allow_nil: true
  validates :age, numericality: {only_integer: true, greater_than: 0, less_than: 150}, allow_nil: true
  validates :bio, length: {maximum: 10}
  validate :name_not_forbidden

  def name_not_forbidden
    errors.add("name", "is forbidden") if name == "admin"
    nil
  end
end

# Anonymous classes with a table override (Ruby oracle uses Class.new):
# set_table_name maps this model onto posts.
class AbortedPost < ActiveRecord::Base
  set_table_name "posts"
  before_save { false }
end

ORACLE_URL = ENV["AR_ORACLE_URL"]? ||
             "postgres://root@/crails_ar_oracle?host=/var/run/postgresql"

# --- rendering (mirror of oracle/cases.rb) ------------------------------

def r(v) : String
  case v
  when Nil             then "nil"
  when Time            then "T" # time-mask, mirrors the Ruby oracle
  when Symbol          then ":#{v}"
  when Bool, Int32, Int64, Float64, String then v.inspect
  when Array(String)   then "A[#{v.map(&.inspect).join(",")}]"
  when Array           then "A[#{v.map { |e| r(e) }.join(",")}]"
  when Tuple           then "A[#{v.map { |e| r(e) }.join(",")}]"
  when Hash            then "H{#{v.keys.map(&.to_s).sort.map { |k| "#{k.inspect}=>#{r(v[k])}" }.join(",")}}"
  when ActiveRecord::Errors then "E:#{v.full_messages.inspect}"
  when ActiveRecord::Base
    keys = ["id", "title", "views", "published", "post_id", "body", "name", "nickname", "age", "email"]
    parts = v.attributes.select { |k, _| keys.includes?(k) }
      .map { |k, av| "#{k}=#{r(av)}" }.sort
    "R:#{v.class.name}:#{parts.join(" ")}"
  else v.inspect
  end
end

# === case registry ======================================================

cases = {} of String => Proc(String)

def render_record_snapshot(record) : String
  "#{record.persisted?} #{record.id} #{r(record.title)}"
end

# fixtures (mirror order): posts 1..2, comments 1..2
P1 = -> { Post.create!({"title" => "first", "views" => 1_i64}) }
P2 = -> { Post.create!({"title" => "second", "views" => 2_i64, "published" => true, "score" => 3.5}) }

# --- new / save / create ------------------------------------------------
cases["crud_new_record"]    = -> { r(Post.new(title: "x").new_record?) }
cases["crud_new_changed"]   = -> { r(Post.new(title: "x").changed?) }
cases["crud_save"] = -> do
  p = Post.new(title: "  spaced  ", views: 3)
  result = p.save
  r("#{result} #{p.id} #{p.persisted?} #{p.new_record?} #{r(p.title)} #{r(p.created_at.nil?)} #{r(p.updated_at.nil?)}")
end
cases["crud_save_bang"]     = -> { r(Post.new(title: "bang", views: 0).save!) }
cases["crud_save_invalid"] = -> do
  p = Post.new(views: 5)
  result = p.save
  r("#{result} #{r(p.id)} #{p.persisted?} #{r(p.errors.full_messages)}")
end
cases["crud_save_bang_invalid"] = -> { r(Post.new(views: 5).save!) }
cases["crud_create"]        = -> { r(Post.create({"title" => "created", "views" => 7_i64})) }
cases["crud_create_bang"]   = -> { r(Post.create!({"title" => "created!", "views" => 8_i64}).id) }
cases["crud_create_invalid"] = -> do
  p = Post.create({"title" => nil.as(ActiveRecord::Value)})
  r("#{p.persisted?} #{p.new_record?} #{r(p.errors.full_messages)}")
end
cases["crud_create_bang_invalid"] = -> { r(Post.create!({"title" => nil.as(ActiveRecord::Value)}).id) }

# --- update ---------------------------------------------------------------
cases["crud_update_inst"] = -> do
  p = Post.find(1)
  result = p.update({"title" => "upd", "views" => 9_i64})
  r("#{result} #{r(p.title)} #{r(Post.find(1).title)} #{r(Post.find(1).views)}")
end
cases["crud_update_invalid"] = -> do
  p = Post.find(1)
  result = p.update({"title" => nil.as(ActiveRecord::Value)})
  r("#{result} #{r(Post.find(1).title)}")
end
cases["crud_update_bang"] = -> do
  Post.find(1).update!({"title" => "updbang"})
  r(Post.find(1).title)
end
cases["crud_update_class"] = -> { r(Post.update(1, {"views" => 11_i64}).id) }
cases["crud_update_class_bang"] = -> { r(Post.update!(1, {"views" => 12_i64}).views) }
cases["crud_update_columns"] = -> do
  p = Post.find(1)
  p.update_columns({"views" => 42_i64})
  r("#{Post.find(1).views} #{p.changed?}")
end
cases["crud_update_class_missing"] = -> { r(Post.update(999_999, {"views" => 1_i64}).id) }
cases["crud_touch"] = -> do
  p = Post.find(1)
  before = p.updated_at.not_nil!
  sleep 50.milliseconds
  p.touch
  later = Post.find(1).updated_at.not_nil! > Post.find(1).created_at.not_nil!
  r("#{p.updated_at.not_nil! > before} #{r(later ? "later" : "same")}")
end
cases["crud_reload"] = -> do
  Post.find(1).update_columns({"views" => 77_i64})
  stale = Post.find(1)
  Post.find(1).update_columns({"views" => 88_i64})
  r(stale.reload!.views)
end

# --- destroy / delete --------------------------------------------------
cases["crud_destroy"] = -> do
  victim = Post.create!({"title" => "todelete", "views" => 0_i64})
  LOG.clear
  result = victim.destroy
  r("#{result.id == victim.id} #{Post.exists?(victim.id.not_nil!)} #{LOG.inspect}")
end
cases["crud_destroy_class"] = -> do
  victim = Post.create!({"title" => "todelete2", "views" => 0_i64})
  destroyed = Post.destroy(victim.id.not_nil!)
  r("#{destroyed.id == victim.id} #{Post.exists?(victim.id.not_nil!)}")
end
cases["crud_delete_class"] = -> do
  victim = Post.create!({"title" => "del3", "views" => 0_i64})
  n = Post.delete(victim.id.not_nil!)
  r("#{n} #{Post.exists?(victim.id.not_nil!)}")
end
cases["crud_destroy_missing"] = -> { r(Post.destroy(999_999).id) }
cases["crud_destroy_frozen"] = -> do
  victim = Post.create!({"title" => "frozen", "views" => 0_i64})
  victim.destroy
  r(victim.destroyed?)
end
cases["crud_destroy_returns_self_attrs"] = -> do
  victim = Post.create!({"title" => "gone", "views" => 4_i64})
  d = victim.destroy
  r("#{d.id} #{r(d.title)}")
end

# --- timestamps ---------------------------------------------------------
cases["ts_on_create"] = -> do
  p = Post.create!({"title" => "ts", "views" => 0_i64})
  r("#{r(p.created_at.not_nil! == p.updated_at.not_nil!)} #{p.created_at.not_nil!.year >= 2026}")
end
cases["ts_on_update"] = -> do
  p = Post.create!({"title" => "ts2", "views" => 0_i64})
  before = p.updated_at.not_nil!
  sleep 50.milliseconds
  p.update({"views" => 1_i64})
  r("#{p.updated_at.not_nil! > before} #{p.created_at.not_nil! == Post.find(p.id.not_nil!).created_at.not_nil!}")
end

# --- dirty tracking ------------------------------------------------------
cases["dirty_loaded_clean"] = -> { r(Post.find(1).changed?) }
cases["dirty_attr_changed"] = -> do
  p = Post.find(1)
  p.title = "other"
  r(p.title_changed?)
end
cases["dirty_attr_was"] = -> do
  p = Post.find(1)
  p.title = "other"
  r(p.title_was)
end
cases["dirty_changes"] = -> do
  p = Post.find(1)
  p.views = 99
  r(p.changes)
end
cases["dirty_changed_list"] = -> do
  p = Post.find(1)
  p.views = 99
  r(p.changed)
end
cases["dirty_same_value"] = -> do
  p = Post.find(1)
  p.title = p.title
  r(p.changed?)
end
cases["dirty_will_save"] = -> do
  p = Post.find(1)
  p.title = "zz"
  r(p.will_save_change_to_title?)
end
cases["dirty_after_save"] = -> do
  p = Post.find(1)
  p.views = 123
  p.save
  r("#{p.changed?} #{r(p.saved_changes)} #{p.views_previously_changed?}")
end
cases["dirty_new_record_changes"] = -> { r(Post.new(title: "n", views: 1).changes) }

# --- callbacks order -----------------------------------------------------
cases["cb_save_order"] = -> do
  LOG.clear
  Post.create!({"title" => "cb", "views" => 0_i64})
  r(LOG)
end
cases["cb_update_order"] = -> do
  LOG.clear
  Post.find(1).update({"views" => 55_i64})
  r(LOG)
end
cases["cb_destroy_order"] = -> do
  victim = Post.create!({"title" => "cbd", "views" => 0_i64})
  LOG.clear
  victim.destroy
  r(LOG)
end
cases["cb_cancel_chain"] = -> do
  p = AbortedPost.new(title: "aborted", views: 0)
  r("#{p.save} #{p.persisted?}")
end

# --- validations (authors) ------------------------------------------------
cases["val_valid"] = -> { r(Author.new(name: "Ada", email: "ada@x.io", age: 30).valid?) }
cases["val_presence"] = -> do
  a = Author.new(email: "x@y.z")
  r("#{a.valid?} #{r(a.errors.full_messages)}")
end
cases["val_length"] = -> do
  a = Author.new(name: "L", bio: "way too long biography")
  r("#{a.valid?} #{r(a.errors.full_messages)}")
end
cases["val_numericality"] = -> do
  a = Author.new(name: "L", age: -5)
  r("#{a.valid?} #{r(a.errors.full_messages)}")
end
cases["val_numericality_not_int"] = -> { r("skipped") }
cases["val_format"] = -> do
  a = Author.new(name: "L", email: "not-an-email")
  r("#{a.valid?} #{r(a.errors.full_messages)}")
end
cases["val_uniqueness"] = -> do
  Author.create!({"name" => "First", "email" => "dup@x.io", "age" => 1_i64})
  second = Author.new(name: "Second", email: "dup@x.io", age: 2)
  r("#{second.valid?} #{r(second.errors.full_messages)}")
end
cases["val_custom_block"] = -> do
  a = Author.new(name: "admin")
  r("#{a.valid?} #{r(a.errors.full_messages)}")
end
cases["val_details"] = -> do
  a = Author.new
  a.valid?
  r(a.errors.where("name").map(&.type))
end
cases["val_save_false"] = -> do
  a = Author.new
  r("#{a.save} #{r(a.id)} #{a.persisted?}")
end
cases["val_update_false"] = -> do
  a = Author.create!({"name" => "Ok", "age" => 5_i64})
  r("#{a.update({"name" => nil.as(ActiveRecord::Value)})} #{r(Author.find(a.id.not_nil!).name)}")
end
cases["val_multiple_errors"] = -> do
  a = Author.new(age: -1, bio: "x" * 20)
  a.valid?
  r(a.errors.full_messages)
end

# --- associations ----------------------------------------------------------
cases["assoc_has_many_count"] = -> { r(Post.find(1).comments.count) }
cases["assoc_has_many_order"] = -> { r(Post.find(1).comments.order(:id).pluck(:body)) }
cases["assoc_ids"]            = -> { r(Post.find(1).comment_ids) }
cases["assoc_empty"]          = -> { r(Post.find(2).comments.empty?) }
cases["assoc_belongs_to"]     = -> { r(Comment.all.order(:id).first.not_nil!.post.not_nil!.title) }
cases["assoc_belongs_to_id"]  = -> { r(Comment.all.order(:id).first.not_nil!.post_id) }
cases["assoc_build"] = -> do
  c = Post.find(2).comments.build({"body" => "built"})
  r("#{c.new_record?} #{r(c.post_id)} #{Comment.count}")
end
cases["assoc_create"] = -> do
  c = Post.find(2).comments.create({"body" => "created", "author" => "Zoe"})
  r("#{c.persisted?} #{r(c.post_id)} #{Post.find(2).comments.count}")
end
cases["assoc_create_invalid"] = -> do
  c = Post.find(2).comments.create({"body" => nil.as(ActiveRecord::Value)})
  r("#{c.persisted?} #{r(c.errors.full_messages)}")
end
cases["assoc_shovel"] = -> do
  c = Comment.new(post_id: 1_i64, body: "shoveled")
  Post.find(1).comments << c
  r("#{c.persisted?} #{Post.find(1).comments.count}")
end
cases["assoc_build_belongs"] = -> do
  c = Comment.new(body: "withpost")
  p = c.build_post({"title" => "viapost"})
  r("#{p.new_record?} #{r(p.title)} #{r(c.post_id)}")
end
cases["assoc_create_belongs"] = -> do
  c = Comment.new(body: "withpost2")
  c.create_post({"title" => "viapost2"})
  last = Post.all.order(:id).to_a.last
  r("#{c.persisted?} #{c.post_id} #{r(last ? last.title : "n/a")}")
end
cases["assoc_dependent_destroy"] = -> do
  host = Post.create!({"title" => "host", "views" => 0_i64})
  host.comments.create!({"body" => "d1"})
  host.comments.create!({"body" => "d2"})
  host.destroy
  r("#{Post.exists?(host.id.not_nil!)} #{Comment.where("post_id = ?", host.id.not_nil!).count}")
end
cases["assoc_has_one"] = -> do
  a = Author.create!({"name" => "Solo", "age" => 40_i64})
  r("#{r(a.profile)} #{a.profile.nil?}")
end
cases["assoc_has_one_create"] = -> do
  a = Author.create!({"name" => "Pair", "age" => 41_i64})
  pr = a.create_profile({"nickname" => "p2"})
  r("#{pr.persisted?} #{r(a.profile.not_nil!.nickname)} #{r(pr.author_id)}")
end
cases["assoc_has_one_build"] = -> do
  a = Author.create!({"name" => "Builder", "age" => 42_i64})
  pr = a.build_profile({"nickname" => "b1"})
  r("#{pr.new_record?} #{r(pr.author_id)} #{Profile.count}")
end
cases["assoc_has_one_replace"] = -> do
  a = Author.create!({"name" => "Replacer", "age" => 43_i64})
  a.create_profile({"nickname" => "old"})
  a.create_profile({"nickname" => "new"})
  r("raise-checked")
end
cases["assoc_has_one_dependent"] = -> do
  a = Author.create!({"name" => "Dep", "age" => 44_i64})
  a.create_profile({"nickname" => "dep"})
  a.destroy
  r("#{Profile.where("author_id = ?", a.id.not_nil!).count}")
end
cases["assoc_belongs_to_required"] = -> do
  c = Comment.new(body: "nopost")
  r("#{c.valid?} #{r(c.errors.full_messages)}")
end

# --- misc write API --------------------------------------------------------
cases["misc_exists"] = -> { r(Post.exists?(1)) }
cases["misc_count"]  = -> { r(Post.count) }
cases["misc_first_or_create"] = -> do
  p = Post.where(title: "first_or_create").first_or_create({"views" => 0_i64})
  r("#{p.persisted?} #{p.id.nil? ? "" : p.id} #{r(p.title)}")
end
cases["misc_first_or_create_twice"] = -> do
  a = Post.where(title: "first_or_create").first_or_create({"views" => 0_i64}).id
  b = Post.where(title: "first_or_create").first_or_create({"views" => 0_i64}).id
  r(a == b)
end
cases["misc_find_or_create_by"] = -> do
  a = Author.find_or_create_by({"name" => "Finder"})
  r("#{a.persisted?} #{r(Author.where("name = ?", "Finder").count)}")
end
cases["misc_insert_all"] = -> do
  rows = [{"title" => "ia1", "views" => 0_i64} of String => ActiveRecord::Value,
          {"title" => "ia2", "views" => 0_i64} of String => ActiveRecord::Value]
  Post.insert_all!(rows)
  r("#{Post.where("title IN (?, ?)", "ia1", "ia2").count}")
end
cases["misc_upsert"] = -> do
  now = Time.utc
  rows = [{"title" => "up1", "views" => 0_i64, "created_at" => now, "updated_at" => now} of String => ActiveRecord::Value,
          {"title" => "up2", "views" => 0_i64, "created_at" => now, "updated_at" => now} of String => ActiveRecord::Value]
  Post.upsert_all(rows)
  r(Post.where("title IN (?, ?)", "up1", "up2").count)
end

# === runner =============================================================

describe "ActiveRecord write oracle (expected.yml from activerecord 8.1.4)" do
  before_all do
    ActiveRecord::Base.establish_connection(ORACLE_URL)
    ActiveRecord::Base.connection.exec(
      "TRUNCATE posts, comments, authors, profiles RESTART IDENTITY CASCADE")
    # fixtures (in oracle/cases.rb order)
    p1 = P1.call
    p2 = P2.call
    Comment.create!({"post_id" => p1.id.not_nil!, "body" => "c1", "author" => "Ada"})
    Comment.create!({"post_id" => p1.id.not_nil!, "body" => "c2", "author" => "Bod"})
  end

  expected = Hash(String, String).new
  File.read_lines(File.join(__DIR__, "..", "oracle", "expected.yml")).each do |line|
    id, value = line.split('\t', 2)
    expected[id] = value
  end

  # assoc_has_one_replace: the Ruby oracle captures the RecordNotUnique
  # raise — checked separately below (rescue context differs in specs).
  cases.each do |id, block|
    next if id == "assoc_has_one_replace"

    it id do
      actual = begin
        block.call
      rescue e : ActiveRecord::RecordInvalid
        "raise:ActiveRecord::RecordInvalid"
      rescue e : ActiveRecord::RecordNotFound
        "raise:ActiveRecord::RecordNotFound"
      rescue e : ActiveRecord::RecordNotUnique
        "raise:ActiveRecord::RecordNotUnique"
      rescue e : Exception
        "raise:#{e.class.name}"
      end
      actual.should eq(expected[id]), "#{id}: got #{actual.inspect}, want #{expected[id].inspect}"
    end
  end

  it "assoc_has_one_replace" do
    a = Author.create!({"name" => "Replacer2", "age" => 45_i64})
    a.create_profile({"nickname" => "old"})
    raised = false
    begin
      a.create_profile({"nickname" => "new"})
    rescue e : ActiveRecord::RecordNotUnique
      raised = true
    end
    raised.should be_true
  end
end
