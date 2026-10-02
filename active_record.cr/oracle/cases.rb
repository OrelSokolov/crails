# Synthetic oracle cases for ActiveRecord WRITE slice (Iteration 2).
#
# Run against the ORIGINAL gem on the scratch database:
#   createdb crails_ar_oracle  (see oracle/setup.sql)
#   ruby oracle/cases.rb > oracle/expected.yml
#
# Each line: "<case_id>\t<rendered result>". The same IDs are mirrored
# 1:1 in spec/oracle_spec.cr; the Crystal port must reproduce
# expected.yml exactly (values captured from activerecord 8.1.4).
# The DB is truncated (RESTART IDENTITY) before each run.

require "active_record"

ActiveRecord::Base.establish_connection(
  adapter: "postgresql",
  host: "/var/run/postgresql",
  database: "crails_ar_oracle",
)

ActiveRecord::Base.connection.execute(
  "TRUNCATE posts, comments, authors, profiles RESTART IDENTITY CASCADE")

$log = []

class Post < ActiveRecord::Base
  has_many :comments, dependent: :destroy

  validates :title, presence: true, length: {maximum: 10}
  validates :views, numericality: {only_integer: true, greater_than_or_equal_to: 0}, allow_nil: true

  before_validation :normalize_title
  before_save :upcase_title
  after_create { $log << "after_create" }
  after_update { $log << "after_update" }
  after_destroy { $log << "after_destroy" }
  before_save { $log << "before_save" }

  def normalize_title
    $log << "before_validation"
    self.title = title.strip if title
  end

  def upcase_title
    $log << "skip" if false
  end
end

class Comment < ActiveRecord::Base
  belongs_to :post
  validates :body, presence: true
end

class Author < ActiveRecord::Base
  has_one :profile, dependent: :destroy
  validates :name, presence: true
  validates :email, format: {with: /\A[^@\s]+@[^@\s]+\z/}, uniqueness: true, allow_nil: true
  validates :age, numericality: {only_integer: true, greater_than: 0, less_than: 150}, allow_nil: true
  validates :bio, length: {maximum: 10}
  validate :name_not_forbidden

  def name_not_forbidden
    errors.add(:name, "is forbidden") if name == "admin"
  end
end

class Profile < ActiveRecord::Base
  belongs_to :author
end

def render(v)
  case v
  when true, false, Integer, Float, String then v.inspect
  when Symbol then ":#{v}"
  when nil then "nil"
  when Time then "T" # time-mask: run-time values must not leak into the oracle
  when Array then "A[#{v.map { |e| render(e) }.join(',')}]"
  when Hash then "H{#{v.sort_by { |k, _| k.to_s }.map { |k, val| "#{render(k)}=>#{render(val)}" }.join(',')}}"
  when ActiveRecord::Base then "R:#{v.class.name}:#{v.attributes.slice('id', 'title', 'views', 'published', 'post_id', 'body', 'name', 'nickname', 'age', 'email').map { |k, x| "#{k}=#{render(x)}" }.sort.join(' ')}"
  when ActiveRecord::Errors then "E:#{v.full_messages.inspect}"
  when Exception then "raise:#{v.class.name}"
  else v.inspect
  end
end

def case_run(id)
  puts "#{id}\t#{render(yield)}"
rescue StandardError => e
  puts "#{id}\traise:#{e.class.name}"
end

# === fixtures: posts 1..3, comments, authors ==========================
p1 = Post.create!(title: "first", views: 1)
p2 = Post.create!(title: "second", views: 2, published: true, score: 3.5)
Comment.create!(post: p1, body: "c1", author: "Ada")
Comment.create!(post: p1, body: "c2", author: "Bod")

# --- new / save / create ------------------------------------------------
case_run("crud_new_record")    { Post.new(title: "x").new_record? }
case_run("crud_new_changed")   { Post.new(title: "x").changed? }
case_run("crud_save") do
  p = Post.new(title: "  spaced  ", views: 3)
  result = p.save
  "#{result} #{p.id} #{p.persisted?} #{p.new_record?} #{render(p.title)} #{render(p.created_at.nil?)} #{render(p.updated_at.nil?)}"
end
case_run("crud_save_bang")     { Post.new(title: "bang", views: 0).save! }
case_run("crud_save_invalid") do
  p = Post.new(views: 5)
  result = p.save
  "#{result} #{render(p.id)} #{p.persisted?} #{render(p.errors.full_messages)}"
end
case_run("crud_save_bang_invalid") { Post.new(views: 5).save! }
case_run("crud_create")        { Post.create(title: "created", views: 7) }
case_run("crud_create_bang")   { Post.create!(title: "created!", views: 8).id }
case_run("crud_create_invalid") do
  p = Post.create(title: nil)
  "#{p.persisted?} #{p.new_record?} #{render(p.errors.full_messages)}"
end
case_run("crud_create_bang_invalid") { Post.create!(title: nil) }

# --- update ---------------------------------------------------------------
case_run("crud_update_inst") do
  p = Post.find(1)
  r = p.update(title: "upd", views: 9)
  "#{r} #{render(p.title)} #{render(Post.find(1).title)} #{render(Post.find(1).views)}"
end
case_run("crud_update_invalid") do
  p = Post.find(1)
  r = p.update(title: nil)
  "#{r} #{render(Post.find(1).title)}"
end
case_run("crud_update_bang") do
  Post.find(1).update!(title: "updbang")
  Post.find(1).title
end
case_run("crud_update_class") { Post.update(1, views: 11).id }
case_run("crud_update_class_bang") { Post.update!(1, views: 12).views }
case_run("crud_update_columns") do
  p = Post.find(1)
  p.update_columns(views: 42)
  "#{Post.find(1).views} #{p.changed?}"
end
case_run("crud_update_class_missing") { Post.update(999999, views: 1) }
case_run("crud_touch") do
  p = Post.find(1)
  before = p.updated_at
  sleep 0.05
  p.touch
  "#{p.updated_at > before} #{Post.find(1).updated_at > Post.find(1).created_at ? render('later') : render('same')}"
end
case_run("crud_reload") do
  Post.find(1).update_columns(views: 77)
  stale = Post.find(1)
  Post.find(1).update_columns(views: 88)
  stale.reload.views
end

# --- destroy / delete ------------------------------------------------------
case_run("crud_destroy") do
  victim = Post.create!(title: "todelete", views: 0)
  $log.clear
  result = victim.destroy
  "#{result.id == victim.id} #{Post.exists?(victim.id)} #{$log.inspect}"
end
case_run("crud_destroy_class") do
  victim = Post.create!(title: "todelete2", views: 0)
  ActiveRecord::Base.connection.execute("SELECT 1")
  destroyed = Post.destroy(victim.id)
  "#{destroyed.id == victim.id} #{Post.exists?(victim.id)}"
end
case_run("crud_delete_class") do
  victim = Post.create!(title: "del3", views: 0)
  n = Post.delete(victim.id)
  "#{n} #{Post.exists?(victim.id)}"
end
case_run("crud_destroy_missing") { Post.destroy(999999) }
case_run("crud_destroy_frozen") do
  victim = Post.create!(title: "frozen", views: 0)
  victim.destroy
  victim.frozen?
end
case_run("crud_destroy_returns_self_attrs") do
  victim = Post.create!(title: "gone", views: 4)
  d = victim.destroy
  "#{d.id} #{render(d.title)}"
end

# --- timestamps ---------------------------------------------------------
case_run("ts_on_create") do
  p = Post.create!(title: "ts", views: 0)
  "#{render(p.created_at.getutc == p.updated_at.getutc)} #{p.created_at.getutc.year >= 2026}"
end
case_run("ts_on_update") do
  p = Post.create!(title: "ts2", views: 0)
  before = p.updated_at
  sleep 0.05
  p.update(views: 1)
  "#{p.updated_at > before} #{p.created_at == Post.find(p.id).created_at}"
end

# --- dirty tracking -------------------------------------------------------
case_run("dirty_loaded_clean") { Post.find(1).changed? }
case_run("dirty_attr_changed") { p = Post.find(1); p.title = "other"; p.title_changed? }
case_run("dirty_attr_was")     { p = Post.find(1); p.title = "other"; p.title_was }
case_run("dirty_changes")      { p = Post.find(1); p.views = 99; p.changes }
case_run("dirty_changed_list") { p = Post.find(1); p.views = 99; p.changed }
case_run("dirty_same_value")   { p = Post.find(1); p.title = p.title; p.changed? }
case_run("dirty_will_save")   { p = Post.find(1); p.title = "zz"; p.will_save_change_to_title? }
case_run("dirty_after_save") do
  p = Post.find(1)
  p.views = 123
  p.save
  "#{p.changed?} #{render(p.saved_changes)} #{p.views_previously_changed?}"
end
case_run("dirty_new_record_changes") { Post.new(title: "n", views: 1).changes }

# --- callbacks order --------------------------------------------------
case_run("cb_save_order") do
  $log.clear
  Post.create!(title: "cb", views: 0)
  $log
end
case_run("cb_update_order") do
  $log.clear
  Post.find(1).update(views: 55)
  $log
end
case_run("cb_destroy_order") do
  victim = Post.create!(title: "cbd", views: 0)
  $log.clear
  victim.destroy
  $log
end
case_run("cb_cancel_chain") do
  klass = Class.new(ActiveRecord::Base) do
    self.table_name = "posts"
    before_save { throw(:abort) }
  end
  p = klass.new(title: "aborted", views: 0)
  "#{p.save} #{p.persisted?}"
end

# --- validations (authors) ------------------------------------------------
case_run("val_valid") { Author.new(name: "Ada", email: "ada@x.io", age: 30).valid? }
case_run("val_presence") do
  a = Author.new(email: "x@y.z")
  "#{a.valid?} #{render(a.errors.full_messages)}"
end
case_run("val_length") do
  a = Author.new(name: "L", bio: "way too long biography")
  "#{a.valid?} #{render(a.errors.full_messages)}"
end
case_run("val_numericality") do
  a = Author.new(name: "L", age: -5)
  "#{a.valid?} #{render(a.errors.full_messages)}"
end
case_run("val_numericality_not_int") do
  # Crystal: статически типизированные атрибуты — строки в Int-колонку
  # не компилируются, кейс непереносим (см. PLAN). Числовой кейс выше
  # покрывает numericality на границах.
  "skipped"
end
case_run("val_format") do
  a = Author.new(name: "L", email: "not-an-email")
  "#{a.valid?} #{render(a.errors.full_messages)}"
end
case_run("val_uniqueness") do
  Author.create!(name: "First", email: "dup@x.io", age: 1)
  second = Author.new(name: "Second", email: "dup@x.io", age: 2)
  "#{second.valid?} #{render(second.errors.full_messages)}"
end
case_run("val_custom_block") do
  a = Author.new(name: "admin")
  "#{a.valid?} #{render(a.errors.full_messages)}"
end
case_run("val_details") do
  a = Author.new
  a.valid?
  a.errors.where(:name).map { |e| e.type }
end
case_run("val_save_false") do
  a = Author.new
  "#{a.save} #{render(a.id)} #{a.persisted?}"
end
case_run("val_update_false") do
  a = Author.create!(name: "Ok", age: 5)
  "#{a.update(name: nil)} #{render(Author.find(a.id).name)}"
end
case_run("val_multiple_errors") do
  a = Author.new(age: -1, bio: "x" * 20)
  a.valid?
  a.errors.full_messages
end

# --- associations --------------------------------------------------------
case_run("assoc_has_many_count") { Post.find(1).comments.count }
case_run("assoc_has_many_order") { Post.find(1).comments.order(:id).pluck(:body) }
case_run("assoc_ids")            { Post.find(1).comment_ids }
case_run("assoc_empty")          { Post.find(2).comments.empty? }
case_run("assoc_belongs_to")     { Comment.order(:id).first.post.title }
case_run("assoc_belongs_to_id")  { Comment.order(:id).first.post_id }
case_run("assoc_build") do
  c = Post.find(2).comments.build(body: "built")
  "#{c.new_record?} #{render(c.post_id)} #{Comment.count}"
end
case_run("assoc_create") do
  c = Post.find(2).comments.create(body: "created", author: "Zoe")
  "#{c.persisted?} #{render(c.post_id)} #{Post.find(2).comments.count}"
end
case_run("assoc_create_invalid") do
  c = Post.find(2).comments.create(body: nil)
  "#{c.persisted?} #{render(c.errors.full_messages)}"
end
case_run("assoc_shovel") do
  c = Comment.new(post_id: 1, body: "shoveled")
  Post.find(1).comments << c
  "#{c.persisted?} #{Post.find(1).comments.count}"
end
case_run("assoc_build_belongs") do
  c = Comment.new(body: "withpost")
  p = c.build_post(title: "viapost")
  "#{p.new_record?} #{render(p.title)} #{render(c.post_id)}"
end
case_run("assoc_create_belongs") do
  c = Comment.new(body: "withpost2")
  c.create_post(title: "viapost2")
  "#{c.persisted?} #{render(c.post_id)} #{render(Post.last.title) rescue render('n/a')}"
end
case_run("assoc_dependent_destroy") do
  host = Post.create!(title: "host", views: 0)
  host.comments.create!(body: "d1")
  host.comments.create!(body: "d2")
  n = host.destroy
  "#{Post.exists?(host.id)} #{Comment.where(post_id: host.id).count}"
end
case_run("assoc_has_one") do
  a = Author.create!(name: "Solo", age: 40)
  "#{render(a.profile)} #{a.profile.nil?}"
end
case_run("assoc_has_one_create") do
  a = Author.create!(name: "Pair", age: 41)
  pr = a.create_profile(nickname: "p2")
  "#{pr.persisted?} #{render(a.profile.nickname)} #{render(pr.author_id)}"
end
case_run("assoc_has_one_build") do
  a = Author.create!(name: "Builder", age: 42)
  pr = a.build_profile(nickname: "b1")
  "#{pr.new_record?} #{render(pr.author_id)} #{Profile.count}"
end
case_run("assoc_has_one_replace") do
  a = Author.create!(name: "Replacer", age: 43)
  a.create_profile(nickname: "old")
  a.create_profile(nickname: "new")
  "#{render(a.profile.nickname)} #{Profile.where(author_id: a.id).count}"
end
case_run("assoc_has_one_dependent") do
  a = Author.create!(name: "Dep", age: 44)
  a.create_profile(nickname: "dep")
  a.destroy
  "#{Profile.where(author_id: a.id).count}"
end
case_run("assoc_belongs_to_required") do
  c = Comment.new(body: "nopost")
  "#{c.valid?} #{render(c.errors.full_messages)}"
end

# --- misc write API -----------------------------------------------------
case_run("misc_exists")  { Post.exists?(1) }
case_msg = ActiveRecord::Base.connection.execute("SELECT count(*) AS n FROM posts").first["n"]
case_run("misc_count")   { Post.count }
case_run("misc_first_or_create") do
  p = Post.where(title: "first_or_create").first_or_create(views: 0)
  "#{p.persisted?} #{p.id} #{render(p.title)}"
end
case_run("misc_first_or_create_twice") do
  Post.where(title: "first_or_create").first_or_create(views: 0).id ==
    Post.where(title: "first_or_create").first_or_create(views: 0).id
end
case_run("misc_find_or_create_by") do
  a = Author.find_or_create_by(name: "Finder")
  "#{a.persisted?} #{render(Author.where(name: "Finder").count)}"
end
case_run("misc_insert_all") do
  n = Post.insert_all!([{title: "ia1", views: 0}, {title: "ia2", views: 0}])
  "#{Post.where(title: %w[ia1 ia2]).count}"
end
case_run("misc_upsert") do
  Post.upsert_all([{title: "up1", views: 0, created_at: Time.now.utc, updated_at: Time.now.utc},
                   {title: "up2", views: 0, created_at: Time.now.utc, updated_at: Time.now.utc}])
  Post.where(title: %w[up1 up2]).count
end
