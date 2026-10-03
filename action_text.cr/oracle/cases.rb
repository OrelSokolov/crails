# Oracle cases for ActionText (Iteration 5, P0 scope: has_rich_text +
# RichText + Content/Fragment + plain-text conversion + serialization +
# sanitize/to_s layout; attachments/sgid are P1).
#
# Run against the ORIGINAL gem:
#   ruby oracle/cases.rb > oracle/expected.yml
#
# Each line: "<case_id>\t<value>". Mirrored 1:1 in spec/oracle_spec.cr;
# the Crystal port must reproduce expected.yml exactly (captured from
# actiontext 8.1.4, Nokogiri HTML5, SQLite in-memory, Disk service for
# the embeds association).
#
# Random values (ids, timestamps) are normalized to shapes/derived facts.

gem "actiontext", "= 8.1.4"
gem "activestorage", "= 8.1.4"
gem "activerecord", "= 8.1.4"
gem "activesupport", "= 8.1.4"
gem "actionpack", "= 8.1.4"
gem "sqlite3", ">= 2.1"
require "action_text"
require "active_storage"
require "tmpdir"

# Standalone ActiveStorage setup (RichText has_many_attached :embeds).
ActiveRecord::Base.include ActiveStorage::Attached::Model
require "active_storage/reflection"
ActiveRecord::Reflection.singleton_class.prepend ActiveStorage::Reflection::ReflectionExtension
ActiveRecord::Base.include ActiveStorage::Reflection::ActiveRecordExtensions

AS_GEM = Gem::Specification.find_by_name("activestorage", "= 8.1.4").gem_dir
require "#{AS_GEM}/app/models/active_storage/record.rb"
require "#{AS_GEM}/app/models/active_storage/filename.rb"
module ActiveStorage
  class Blob < ActiveStorage::Record
    self.table_name = "active_storage_blobs"
  end
end
require "#{AS_GEM}/app/models/active_storage/blob/analyzable.rb"
require "#{AS_GEM}/app/models/active_storage/blob/identifiable.rb"
require "#{AS_GEM}/app/models/active_storage/blob/representable.rb"
require "#{AS_GEM}/app/models/active_storage/blob/servable.rb"
require "#{AS_GEM}/app/models/active_storage/blob.rb"
module ActiveStorage
  class Attachment < ActiveStorage::Record
    self.table_name = "active_storage_attachments"
  end
end
require "#{AS_GEM}/app/models/active_storage/attachment.rb"

module Rails
  def self.configuration
    @configuration ||= Config.new
  end

  class Config
    def active_storage
      @active_storage ||= StorageConfig.new
    end

    class StorageConfig
      attr_accessor :service

      def initialize
        @service = :local # non-nil skips the global-service validation
      end
    end
  end
end

AT_GEM = Gem::Specification.find_by_name("actiontext", "= 8.1.4").gem_dir
# app/helpers are railtie autoload territory: load by hand BEFORE rich_text
# (Content includes ContentHelper at load time).
require "#{AT_GEM}/app/helpers/action_text/content_helper.rb"
require "#{AT_GEM}/app/models/action_text/record.rb"
require "#{AT_GEM}/app/models/action_text/rich_text.rb"
# The engine's isolated namespace sets the prefix; standalone we pin it.
ActionText::RichText.table_name = "action_text_rich_texts"

ActiveRecord::Migration.verbose = false
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.define do
  create_table :messages
  create_table :action_text_rich_texts do |t|
    t.string   :name,        null: false
    t.text     :body
    t.string   :record_type, null: false
    t.bigint   :record_id,   null: false
    t.datetime :created_at,  null: false
    t.datetime :updated_at,  null: false
  end
  create_table :active_storage_blobs do |t|
    t.string   :key,          null: false
    t.string   :filename,     null: false
    t.string   :content_type
    t.text     :metadata
    t.string   :service_name, null: false
    t.bigint   :byte_size,    null: false
    t.string   :checksum
    t.datetime :created_at,   null: false
  end
  create_table :active_storage_attachments do |t|
    t.string   :name,         null: false
    t.string   :record_type,  null: false
    t.integer  :record_id,    null: false
    t.integer  :blob_id,      null: false
    t.datetime :created_at,   null: false
  end
end

require "active_storage/service"
require "active_storage/service/disk_service"
require "active_storage/service/registry"
ROOT = Dir.mktmpdir("at_oracle")
ActiveStorage::Blob.services = ActiveStorage::Service::Registry.new(
  {"Local" => {"service" => "Disk", "root" => ROOT}})
ActiveStorage::Blob.service = ActiveStorage::Blob.services.fetch("Local")

# Renderer for Content#to_s (layout). The engine normally registers the
# helper and the app holds the view paths; standalone we wire both.
require "action_controller"
ActionController::Base.append_view_path("#{AT_GEM}/app/views")
ActionController::Base.helper ActionText::ContentHelper

# Railtie normally wires this; standalone we include by hand.
ActiveRecord::Base.include ActionText::Attribute

class Message < ActiveRecord::Base
  has_rich_text :content
end

def render(v)
  s = v.is_a?(String) ? v : v.inspect
  # keep the id\tvalue line protocol: escape embedded control chars
  s.gsub("\\", "\\\\\\\\").gsub("\n", "\\n").gsub("\t", "\\t").gsub("\r", "\\r")
end

def case_run(id)
  puts "#{id}\t#{render(yield)}"
rescue StandardError => e
  puts "#{id}\traise:#{e.class.name}"
end

CONTENT = ActionText::Content

# --- Content: HTML serialization (Nokogiri HTML5 fragment) ------------
case_run("html_h1")      { CONTENT.new("<h1>Funny times!</h1>").to_html }
case_run("html_script")  { CONTENT.new("<div onclick='action()'>safe<script>unsafe()</script></div>").to_html }
case_run("html_br")      { CONTENT.new("line1<br>line2").to_html }
case_run("html_entity")  { CONTENT.new("&lt;script&gt;alert()&lt;/script&gt;").to_html }
case_run("html_empty")   { CONTENT.new("").to_html }
case_run("html_strip")   { CONTENT.new("   <p>x</p>   ").to_html }
case_run("html_list")    { CONTENT.new("<ul><li>one</li><li>two</li></ul>").to_html }
case_run("html_inline")  { CONTENT.new("<strong>bold</strong> and <em>it</em>").to_html }
case_run("html_newline") { CONTENT.new("<h1>a</h1>\n<p>b</p>").to_html }

# --- Content: to_plain_text -------------------------------------------
case_run("pt_h1")        { CONTENT.new("<h1>Funny times!</h1>").to_plain_text }
case_run("pt_div_script"){ CONTENT.new("<div onclick='action()'>safe<script>unsafe()</script></div>").to_plain_text }
case_run("pt_blocks")    { CONTENT.new("<h1>T</h1><p>P</p>").to_plain_text }
case_run("pt_divs")      { CONTENT.new("<div>d1</div><div>d2</div>").to_plain_text }
case_run("pt_br")        { CONTENT.new("a<br>b").to_plain_text }
case_run("pt_ul")        { CONTENT.new("<ul><li>one</li><li>two</li></ul>").to_plain_text }
case_run("pt_ol")        { CONTENT.new("<ol><li>a</li><li>b</li></ol>").to_plain_text }
case_run("pt_nested_ul") { CONTENT.new("<ul><li>a<ul><li>b</li></ul></li></ul>").to_plain_text }
case_run("pt_blockquote"){ CONTENT.new("<blockquote>quoted</blockquote>").to_plain_text }
case_run("pt_bq_empty")  { CONTENT.new("<blockquote></blockquote>").to_plain_text }
case_run("pt_figcaption"){ CONTENT.new("<figure><figcaption>cap</figcaption></figure>").to_plain_text }
case_run("pt_entity")    { CONTENT.new("&lt;script&gt;alert()&lt;/script&gt;").to_plain_text }
case_run("pt_style")     { CONTENT.new("<style>.x{color:red}</style>text").to_plain_text }
case_run("pt_mixed")     { CONTENT.new("<h1>Doc</h1><div>line</div>tail").to_plain_text }
case_run("pt_empty")     { CONTENT.new("").to_plain_text }

# --- Content: links ----------------------------------------------------
case_run("links_basic")  { CONTENT.new(%(<a href="http://example.com/">E</a>)).links }
case_run("links_uniq")   { CONTENT.new(%(<a href="http://a.io/">1</a><a href="http://a.io/">2</a><a href="https://b.io/x">3</a>)).links }
case_run("links_none")   { CONTENT.new("<p>no links</p>").links }

# --- sanitize (what to_s renders inside the layout) --------------------
helper = Object.new.extend(ActionText::ContentHelper)
case_run("sz_script")  { helper.sanitize_action_text_content(CONTENT.new("<div onclick='action()'>safe<script>unsafe()</script></div>")) }
case_run("sz_kept")    { helper.sanitize_action_text_content(CONTENT.new("<h1>Keep</h1><b>b</b>")) }
case_run("sz_bad_tag") { helper.sanitize_action_text_content(CONTENT.new("<custom>x</custom>y")) }
case_run("sz_href")    { helper.sanitize_action_text_content(CONTENT.new(%(<a href="http://e.com/" onclick="steal()">L</a>))) }

# --- serialization ------------------------------------------------------
case_run("ser_dump")      { CONTENT.dump(CONTENT.new("<b>x</b>")) }
case_run("ser_dump_nil")  { CONTENT.dump(nil) }
case_run("ser_load")      { CONTENT.load("<b>x</b>").to_html }
case_run("ser_load_nil")  { CONTENT.load(nil) }
case_run("ser_roundtrip") { CONTENT.load(CONTENT.dump(CONTENT.new("<p>r</p>"))).to_plain_text }

# --- RichText persistence via has_rich_text ----------------------------
MSG = Message.create!(content: "<h1>Funny times!</h1>")

case_run("rt_plain")     { MSG.content.to_plain_text }
case_run("rt_present")   { MSG.content? }
case_run("rt_row") do
  row = ActionText::RichText.where(record_type: "Message", record_id: MSG.id).sole
  [row.name, row.record_type, row.record_id == MSG.id, row.body.to_html]
end
case_run("rt_body_db")   { ActiveRecord::Base.connection.select_value("SELECT body FROM action_text_rich_texts") }
case_run("rt_reload")    { Message.find(MSG.id).content.to_plain_text }
case_run("rt_update") do
  m = Message.find(MSG.id)
  m.content = "Updated <b>bold</b>"
  m.save!
  [Message.find(MSG.id).content.to_plain_text,
   ActionText::RichText.where(record_type: "Message").count]
end
case_run("rt_absent")     { Message.create!.content? }
case_run("rt_blank_body") { Message.create!(content: "").content? }

case_run("rt_entity")  { Message.create!(content: "&lt;script&gt;alert()&lt;/script&gt;").content.to_plain_text }
case_run("rt_to_s")    { Message.create!(content: "<h1>Funny times!</h1>").content.to_s }
case_run("rt_to_s_div"){ Message.create!(content: "<div>d</div>").content.to_s }
case_run("rt_to_s_san"){ Message.create!(content: "<div onclick='a()'>safe<script>u()</script></div>").content.to_s }
