# Oracle cases for the turbo.cr port (turbo-rails 2.0.x, Turbo Streams).
#
# Run against the ORIGINAL gem on the scratch database:
#   createdb crails_turbo_oracle   (once)
#   TZ=UTC ruby oracle/cases.rb > oracle/expected.yml
#
# Each line: "<case_id>\t<rendered result>". The same IDs are mirrored 1:1
# in spec/oracle_spec.cr; the Crystal port must reproduce expected.yml
# exactly (values captured from turbo-rails 2.0.20 + rails 8.1.4).
#
# The harness loads the gem's app/ files manually (they are normally
# wired by Zeitwerk inside a Rails app) and stubs ActionCable.server
# with a broadcast-capturing fake — the same seam the gem's own unit
# tests use. Deterministic ids: tables are TRUNCATEd RESTART IDENTITY.

ENV["TZ"] = "UTC"

require "rails"
require "turbo-rails"
require "active_record"
require "action_view"
require "action_cable"
require "action_controller"
require "globalid"
require "active_job"
require "rack/mock"

module Turbo::Streams; end
GEM = Gem.loaded_specs["turbo-rails"].full_gem_path
%w[
  app/channels/turbo/streams/stream_name
  app/helpers/turbo/streams/action_helper
  app/channels/turbo/streams/broadcasts
  app/models/turbo/streams/tag_builder
  app/channels/turbo/streams_channel
  app/helpers/turbo/streams_helper
  app/helpers/turbo/frames_helper
  app/models/concerns/turbo/broadcastable
  app/models/turbo/debouncer
  app/models/turbo/thread_debouncer
  app/jobs/turbo/streams/broadcast_job
  app/jobs/turbo/streams/action_broadcast_job
  app/jobs/turbo/streams/broadcast_stream_job
  app/controllers/turbo/streams/turbo_streams_tag_builder
].each { |f| require "#{GEM}/#{f}" }

VIEWS = File.expand_path(__dir__ + "/views")

# The turbo engine registers the MIME type; standalone harness does it
# the same way (turbo/engine.rb initializer "turbo.mimetype").
Mime::Type.register "text/vnd.turbo-stream.html", :turbo_stream

Turbo.signed_stream_verifier_key =
  "b729ff44d0b0e664a193a9f8a2d1c5e7b930aa66ff11d22cc61e0f3d8a4b7c19"
GlobalID.app = "oracle"

ActiveRecord::Base.establish_connection(
  adapter: "postgresql",
  host: "/var/run/postgresql",
  database: "crails_turbo_oracle",
)
ActiveRecord::Base.logger = nil
ActiveJob::Base.logger = nil
ActiveJob::Base.queue_adapter = :inline

conn = ActiveRecord::Base.connection
conn.execute("DROP TABLE IF EXISTS posts")
conn.create_table(:posts) { |t| t.string :title }

# --- broadcast capture: fake ActionCable.server ---------------------

BROADCASTS = []
FAKE_SERVER = Object.new
def FAKE_SERVER.broadcast(name, payload)
  BROADCASTS << [name, payload]
end
module ActionCable
  class << self
    def server
      FAKE_SERVER
    end
  end
end

class ApplicationController < ActionController::Base
  self.view_paths = [VIEWS]
  helper Turbo::StreamsHelper
end

class Post < ActiveRecord::Base
  include GlobalID::Identification
  include Turbo::Broadcastable
end

# Separate model for declarative broadcasts_to cases.
conn.execute("DROP TABLE IF EXISTS messages")
conn.create_table(:messages) { |t| t.string :body }

class Message < ActiveRecord::Base
  include GlobalID::Identification
  include Turbo::Broadcastable
end

class OracleView < ActionView::Base
  include Turbo::StreamsHelper
  include Turbo::FramesHelper
  # Standalone view has no controller prefixes; skipping the namespace
  # merge produces the same partial path a real app resolves to.
  self.prefix_partial_path_with_controller_namespace = false
end

VIEW = OracleView.with_empty_template_cache.new(
  ActionView::LookupContext.new([VIEWS]), [], ApplicationController.new)

def render(v)
  v.inspect
end

def case_run(id)
  BROADCASTS.clear
  puts "#{id}\t#{render(yield)}"
rescue StandardError => e
  puts "#{id}\traise:#{e.class.name}"
ensure
  BROADCASTS.clear
end

def bcasts
  BROADCASTS.map { |n, p| "#{n} #{p.inspect}" }
end

conn.execute("TRUNCATE posts, messages RESTART IDENTITY")

# --- MessageVerifier / stream names ---------------------------------

case_run "verifier_generate_string" do
  Turbo.signed_stream_verifier.generate("entries")
end

case_run "verifier_generate_array" do
  Turbo.signed_stream_verifier.generate([:entries])
end

case_run "verifier_verified_ok" do
  Turbo.signed_stream_verifier.verified(
    Turbo.signed_stream_verifier.generate("entries"))
end

case_run "verifier_verified_tampered" do
  Turbo.signed_stream_verifier.verified("ImVudHJpZXMi--deadbeef")
end

case_run "stream_name_signed_string" do
  Turbo::StreamsChannel.signed_stream_name(["room"])
end

case_run "stream_name_signed_symbol" do
  Turbo::StreamsChannel.signed_stream_name([:entries])
end

post = Post.create!(title: "hello")
case_run "stream_name_signed_record" do
  Turbo::StreamsChannel.signed_stream_name([post])
end

case_run "stream_name_signed_mixed" do
  Turbo::StreamsChannel.signed_stream_name([post, :entries])
end

case_run "stream_name_verified_record" do
  Turbo::StreamsChannel.verified_stream_name(
    Turbo::StreamsChannel.signed_stream_name([post, :entries]))
end

case_run "stream_name_gid_param" do
  post.to_gid_param
end

# --- TagBuilder ------------------------------------------------------

TB = Turbo::Streams::TagBuilder.new(VIEW)

case_run "tb_remove_string" do
  TB.remove("clearance_5")
end

case_run "tb_remove_record" do
  TB.remove(post)
end

case_run "tb_remove_all_selector" do
  TB.remove_all(".clearance_item")
end

case_run "tb_append_content" do
  TB.append("entries", "<div>hi</div>")
end

case_run "tb_append_block" do
  TB.append("entries") { "<b>from block</b>" }
end

case_run "tb_replace_record_renders_partial" do
  TB.replace(post)
end

case_run "tb_update_partial_locals" do
  TB.update("post_1", partial: "posts/post", locals: {post: post})
end

case_run "tb_before_content" do
  TB.before("entry_1", "<li>first</li>")
end

case_run "tb_after_content" do
  TB.after("entry_1", "<li>last</li>")
end

case_run "tb_prepend_html" do
  TB.prepend("entries", html: "<div>prepended</div>")
end

case_run "tb_attributes_morph" do
  TB.replace("post_1", "<div>morphed</div>", method: "morph")
end

case_run "tb_action_custom" do
  TB.action(:highlight, "my-element")
end

case_run "tb_action_all_custom" do
  TB.action_all(:highlight, ".my-elements")
end

case_run "tb_action_all_targets" do
  TB.action_all(:remove, ".items", allow_inferred_rendering: false)
end

# --- View helpers ----------------------------------------------------

case_run "helper_turbo_stream_from_string" do
  VIEW.turbo_stream_from("room")
end

case_run "helper_turbo_stream_from_symbols" do
  VIEW.turbo_stream_from(:entries)
end

case_run "helper_turbo_stream_from_record" do
  VIEW.turbo_stream_from(post, :entries)
end

case_run "helper_turbo_stream_from_blank" do
  VIEW.turbo_stream_from("")
end

case_run "helper_turbo_stream_from_data" do
  VIEW.turbo_stream_from("room", data: {room_name: "room #1"})
end

case_run "helper_turbo_frame_tag" do
  VIEW.turbo_frame_tag("frame1")
end

case_run "helper_turbo_frame_tag_src" do
  VIEW.turbo_frame_tag("frame1", src: "/posts", loading: "lazy")
end

case_run "helper_turbo_frame_tag_block" do
  VIEW.turbo_frame_tag("frame1") { "<p>inside</p>" }
end

# --- Broadcasts (Turbo::StreamsChannel) ------------------------------

case_run "bcast_remove_to" do
  Turbo::StreamsChannel.broadcast_remove_to(:entries, target: post)
  bcasts
end

case_run "bcast_remove_to_targets" do
  Turbo::StreamsChannel.broadcast_remove_to(:entries, targets: ".items")
  bcasts
end

case_run "bcast_append_to_partial" do
  Turbo::StreamsChannel.broadcast_append_to(:entries, target: "posts",
    partial: "posts/post", locals: {post: post})
  bcasts
end

case_run "bcast_replace_to_html" do
  Turbo::StreamsChannel.broadcast_replace_to(:entries, target: "post_1",
    html: "<p>HTML</p>")
  bcasts
end

case_run "bcast_update_to_content" do
  Turbo::StreamsChannel.broadcast_update_to(:entries, target: "post_count",
    content: "<span>1</span>")
  bcasts
end

case_run "bcast_before_to" do
  Turbo::StreamsChannel.broadcast_before_to(:entries, target: "entry_1",
    html: "<li>first</li>")
  bcasts
end

case_run "bcast_after_to" do
  Turbo::StreamsChannel.broadcast_after_to(:entries, target: "entry_1",
    html: "<li>last</li>")
  bcasts
end

case_run "bcast_refresh_to" do
  Turbo::StreamsChannel.broadcast_refresh_to(:entries)
  bcasts
end

case_run "bcast_refresh_to_request_id" do
  Turbo::StreamsChannel.broadcast_refresh_to(:entries, request_id: "abc123")
  bcasts
end

case_run "bcast_action_to_morph" do
  Turbo::StreamsChannel.broadcast_action_to(:entries, action: :replace,
    target: "post_1", html: "<div>m</div>", attributes: {method: "morph"})
  bcasts
end

case_run "bcast_action_to_render_false" do
  Turbo::StreamsChannel.broadcast_action_to(:entries, action: :remove,
    target: "post_1", render: false)
  bcasts
end

case_run "bcast_action_to_targets_attributes" do
  Turbo::StreamsChannel.broadcast_action_to(:entries, action: :remove,
    targets: ".items", render: false, attributes: {"data-test" => "1"})
  bcasts
end

case_run "bcast_stream_to_raw" do
  Turbo::StreamsChannel.broadcast_stream_to(:entries,
    content: "<turbo-stream action=\"refresh\"></turbo-stream>")
  bcasts
end

case_run "bcast_render_to_template" do
  Turbo::StreamsChannel.broadcast_render_to(:entries,
    template: "posts/create", assigns: {post: post})
  bcasts
end

case_run "bcast_append_later_to" do
  Turbo::StreamsChannel.broadcast_append_later_to(:entries, target: "posts",
    partial: "posts/post", locals: {post: post})
  bcasts
end

case_run "bcast_render_later_to" do
  Turbo::StreamsChannel.broadcast_render_later_to(:entries,
    template: "posts/create", assigns: {post: post})
  bcasts
end

case_run "bcast_stream_name_record" do
  Turbo::StreamsChannel.broadcast_stream_to(post,
    content: "<turbo-stream action=\"refresh\"></turbo-stream>")
  BROADCASTS.map(&:first)
end

# --- Broadcastable (model concern) -----------------------------------

class Message < ActiveRecord::Base
  broadcasts_to :stream_key, inserts_by: :prepend, target: "messages"

  def stream_key
    :entries
  end
end

case_run "broadcastable_broadcasts_to_create" do
  Message.create!(body: "m1")
  bcasts
end

case_run "broadcastable_broadcasts_to_update" do
  m = Message.first
  m.update!(body: "m2")
  bcasts
end

case_run "broadcastable_broadcasts_to_destroy" do
  m = Message.first
  m.destroy
  bcasts
end

class Message
  # reset declarative callbacks for the next cases
end

case_run "broadcastable_append_default_target_partial" do
  post.broadcast_append_to(:entries)
  bcasts
end

case_run "broadcastable_replace_to_target" do
  post.broadcast_replace_to(:entries, target: "special", html: "<p>r</p>")
  bcasts
end

case_run "broadcastable_remove_no_streamables" do
  post.broadcast_remove
  bcasts
end

case_run "broadcastable_refresh_to" do
  post.broadcast_refresh_to(:entries)
  bcasts
end

case_run "broadcastable_suppressing" do
  Post.suppressing_turbo_broadcasts do
    post.broadcast_remove
  end
  bcasts
end

case_run "broadcastable_update_later_to" do
  post.broadcast_update_later_to(:entries, target: "post_1",
    partial: "posts/post", locals: {post: post})
  bcasts
end

# --- HTTP: format.turbo_stream ---------------------------------------

class PostsController < ApplicationController
  helper Turbo::StreamsHelper

  def create
    @post = Post.create!(title: "http post")
    respond_to do |format|
      format.turbo_stream
      # NOTE: absolute URL — the port does not absolutize Location.
      format.html { redirect_to "http://example.org/posts" }
    end
  end
end

case_run "http_create_turbo_stream" do
  resp = Rack::MockRequest.new(PostsController.action(:create))
    .post("", "HTTP_ACCEPT" => "text/vnd.turbo-stream.html, text/html;q=0.1")
  [resp.status, resp.headers["Content-Type"], resp.body]
end

case_run "http_create_html_fallback" do
  resp = Rack::MockRequest.new(PostsController.action(:create))
    .post("", "HTTP_ACCEPT" => "text/html")
  [resp.status, resp.headers["Content-Type"], resp.headers["Location"]]
end
