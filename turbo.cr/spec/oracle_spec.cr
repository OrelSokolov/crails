# Oracle spec: 1:1 mirror of oracle/cases.rb (turbo-rails 2.0.20).
# Expected values live in oracle/expected.yml — captured from the
# ORIGINAL gem on the scratch database. The port must reproduce them
# exactly; the tests are never edited on either side (see AGENTS.md).
#
# Run: make spec   (CRAILS_VIEWS=spec/fixtures/views crystal spec)

require "spec"
require "http"
require "../src/turbo_cr"

DB_URL = ENV["TURBO_SPEC_URL"]? ||
         "postgres://root@/crails_turbo_spec?host=/var/run/postgresql"

# --- harness (mirror of oracle/cases.rb) ------------------------------

Turbo.signed_stream_verifier_key =
  "b729ff44d0b0e664a193a9f8a2d1c5e7b930aa66ff11d22cc61e0f3d8a4b7c19"
Turbo.app = "oracle"

ActiveRecord::Base.establish_connection(DB_URL)

CABLE_PUBSUB = ActionCable::SubscriptionAdapter::Test.new
Turbo.cable_server = ActionCable::Server.new(CABLE_PUBSUB)

# Inline-адаптер (как queue_adapter = :inline в оракуле): джоба
# исполняется в момент perform_later — capture синхронный.
class TurboInlineJobAdapter
  include ActiveJob::Adapter

  def enqueue(record : ActiveJob::EnqueuedJob) : Nil
    ActiveJob::Base.deserialize(record.to_job_data).perform_now
  end
end

ActiveJob.adapter = TurboInlineJobAdapter.new


# Потоки, в которые пишут кейсы (чистятся перед каждым кейсом).
SPEC_STREAMS = ["entries", "Z2lkOi8vb3JhY2xlL1Bvc3QvMQ"]

# --- models ------------------------------------------------------------

class Post < ActiveRecord::Base
  include Turbo::Broadcastable
end

class Message < ActiveRecord::Base
  include Turbo::Broadcastable
  broadcasts_to :stream_key, inserts_by: :prepend, target: "messages"

  def stream_key : Symbol
    :entries
  end
end

# --- view + renderer seam ----------------------------------------------

class TurboView
  include ActionView::Helpers
  include Turbo::StreamsHelper
  include Turbo::FramesHelper

  compile_partials({
    "posts/post"     => {path: "spec/fixtures/views/posts/_post.html.erb", locals: {"post" => Post}},
    "messages/message" => {path: "spec/fixtures/views/messages/_message.html.erb", locals: {"message" => Message}},
  })

  # assigns для turbo_stream-шаблона posts/create.
  property post : Post?

  compile_template "ts_posts_create", "spec/fixtures/views/posts/create.turbo_stream.erb"

  # RenderVal -> union локальных типов партиалов (boilerplate приложения:
  # см. turbo.cr/PLAN.md).
  alias PartialLocal = Union(Post, Message, Int32)

  def render_turbo_partial(partial : String, locals : Hash(String, Turbo::RenderVal)) : String
    h = {} of String => PartialLocal
    locals.each do |k, v|
      h[k] = case v
             when Post    then v
             when Message then v
             when Int32   then v
             else              raise ArgumentError.new("unsupported local #{k}: #{v.class}")
             end
    end
    render(partial, h).to_s
  end
end

VIEW = TurboView.new

Turbo.partial_renderer = ->(partial : String, locals : Hash(String, Turbo::RenderVal)) do
  VIEW.render_turbo_partial(partial, locals)
end

Turbo.template_renderer = ->(template : String, assigns : Hash(String, Turbo::RenderVal)) do
  case template
  when "posts/create"
    v = TurboView.new
    v.post = assigns["post"].as(Post)
    v.ts_posts_create.to_s
  else
    raise ArgumentError.new("unknown turbo_stream template #{template}")
  end
end

TB = Turbo::Streams::TagBuilder.new(VIEW)

# --- HTTP harness (PostsController) ------------------------------------

class PostsController < ActionController::Base
  property post : Post?

  def create
    @post = Post.create!({"title" => "http post"})
    respond_to do |format|
      format.turbo_stream
      # NOTE: absolute URL — the port does not absolutize Location.
      format.html { redirect_to "http://example.org/posts" }
    end
  end
end

private def http_post(action : String, accept : String) : Tuple(Int32, String, String | Nil, String | Nil)
  request = HTTP::Request.new("POST", "/posts", headers: HTTP::Headers{"Accept" => accept})
  io = IO::Memory.new
  response = HTTP::Server::Response.new(io)
  context = HTTP::Server::Context.new(request, response)
  controller = PostsController.new(context)
  controller.__set_params({} of String => String)
  controller.__run_action(action)
  context.response.close
  body = io.to_s
  status = response.status_code
  {status, response.headers["Content-Type"]?.to_s, response.headers["Location"]?, body}
end

# --- runner ------------------------------------------------------------

EXPECTED = Hash(String, String).new.tap do |h|
  File.each_line("#{__DIR__}/../oracle/expected.yml") do |line|
    next if line.blank?
    key, value = line.split("\t", 2)
    h[key] = value
  end
end

private def case_run(id)
  SPEC_STREAMS.each { |s| CABLE_PUBSUB.clear_messages(s) }
  result = yield
  actual = ruby_inspect(result)
  expected = EXPECTED[id]? || raise "no expected value for #{id}"
  actual.should eq(expected.chomp), "#{id}: #{actual}"
rescue e : ArgumentError
  EXPECTED[id].should eq("raise:#{e.class.name}")
ensure
  SPEC_STREAMS.each { |s| CABLE_PUBSUB.clear_messages(s) }
end

private def bcasts : Array(String)
  [] of String
end

private def ruby_inspect(v) : String
  case v
  when Array
    "[" + v.map { |x| ruby_inspect(x) }.join(", ") + "]"
  when Tuple
    "[" + v.map { |x| ruby_inspect(x) }.join(", ") + "]"
  when ActionView::SafeString then v.to_s.inspect
  when String then v.inspect
  when Nil    then "nil"
  else             v.to_s
  end
end

private def captured(streams : Array(String)) : Array(String)
  streams.flat_map { |s| CABLE_PUBSUB.broadcasts(s).map { |p| "#{s} #{p.inspect}" } }
end

# Имена стримов, получившие броадкасты (BROADCASTS.map(&:first) в оракуле).
private def captured_names(streams : Array(String)) : Array(String)
  streams.select { |s| !CABLE_PUBSUB.broadcasts(s).empty? }
end

describe "turbo-rails oracle (expected.yml from turbo-rails 2.0.20)" do
  before_all do
    conn = ActiveRecord::Base.connection
    conn.exec("DROP TABLE IF EXISTS posts")
    conn.exec(%(CREATE TABLE posts (id bigserial PRIMARY KEY, title character varying)))
    conn.exec("DROP TABLE IF EXISTS messages")
    conn.exec(%(CREATE TABLE messages (id bigserial PRIMARY KEY, body character varying)))
    conn.exec("TRUNCATE posts, messages RESTART IDENTITY")
  end

  # capture pubsub-доставки: broadcast_stream_to пишет в Test-адаптер,
  # зеркало bcases читает то же, что оракул перехватил у ActionCable.server
  before_each do
    SPEC_STREAMS.each { |s| CABLE_PUBSUB.clear_messages(s) }
  end

  it "verifier + stream names" do
    case_run "verifier_generate_string" do
      Turbo.signed_stream_verifier.generate("entries")
    end
    case_run "verifier_generate_array" do
      Turbo.signed_stream_verifier.generate(["entries"])
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
    post = Post.create!({"title" => "hello"})
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
  end

  it "TagBuilder" do
    post = Post.first.not_nil!
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
      TB.update("post_1", partial: "posts/post", locals: {"post" => post})
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
  end

  it "view helpers" do
    post = Post.first.not_nil!
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
      VIEW.turbo_stream_from("room", data: {"room_name" => "room #1"})
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
  end

  it "broadcasts" do
    post = Post.first.not_nil!
    gid_stream = post.to_gid_param

    case_run "bcast_remove_to" do
      Turbo::StreamsChannel.broadcast_remove_to([:entries], target: post)
      captured(["entries"])
    end
    case_run "bcast_remove_to_targets" do
      Turbo::StreamsChannel.broadcast_remove_to([:entries], targets: ".items")
      captured(["entries"])
    end
    case_run "bcast_append_to_partial" do
      Turbo::StreamsChannel.broadcast_append_to([:entries], target: "posts",
        partial: "posts/post", locals: {"post" => post})
      captured(["entries"])
    end
    case_run "bcast_replace_to_html" do
      Turbo::StreamsChannel.broadcast_replace_to([:entries], target: "post_1",
        html: "<p>HTML</p>")
      captured(["entries"])
    end
    case_run "bcast_update_to_content" do
      Turbo::StreamsChannel.broadcast_update_to([:entries], target: "post_count",
        content: "<span>1</span>")
      captured(["entries"])
    end
    case_run "bcast_before_to" do
      Turbo::StreamsChannel.broadcast_before_to([:entries], target: "entry_1",
        html: "<li>first</li>")
      captured(["entries"])
    end
    case_run "bcast_after_to" do
      Turbo::StreamsChannel.broadcast_after_to([:entries], target: "entry_1",
        html: "<li>last</li>")
      captured(["entries"])
    end
    case_run "bcast_refresh_to" do
      Turbo::StreamsChannel.broadcast_refresh_to([:entries])
      captured(["entries"])
    end
    case_run "bcast_refresh_to_request_id" do
      Turbo::StreamsChannel.broadcast_refresh_to([:entries])
      captured(["entries"])
    end
    case_run "bcast_action_to_morph" do
      Turbo::StreamsChannel.broadcast_action_to([:entries], :replace,
        target: "post_1", html: "<div>m</div>", attributes: {"method" => "morph"})
      captured(["entries"])
    end
    case_run "bcast_action_to_render_false" do
      Turbo::StreamsChannel.broadcast_action_to([:entries], :remove,
        target: "post_1", render: false)
      captured(["entries"])
    end
    case_run "bcast_action_to_targets_attributes" do
      Turbo::StreamsChannel.broadcast_action_to([:entries], :remove,
        targets: ".items", render: false, attributes: {"data-test" => "1"})
      captured(["entries"])
    end
    case_run "bcast_stream_to_raw" do
      Turbo::StreamsChannel.broadcast_stream_to([:entries],
        content: "<turbo-stream action=\"refresh\"></turbo-stream>")
      captured(["entries"])
    end
    case_run "bcast_render_to_template" do
      Turbo::StreamsChannel.broadcast_render_to([:entries],
        template: "posts/create", assigns: {"post" => post})
      captured(["entries"])
    end
    case_run "bcast_append_later_to" do
      Turbo::StreamsChannel.broadcast_append_later_to([:entries], target: "posts",
        partial: "posts/post", locals: {"post" => post})
      captured(["entries"])
    end
    case_run "bcast_render_later_to" do
      Turbo::StreamsChannel.broadcast_render_later_to([:entries],
        template: "posts/create", assigns: {"post" => post})
      captured(["entries"])
    end
    case_run "bcast_stream_name_record" do
      Turbo::StreamsChannel.broadcast_stream_to([post],
        content: "<turbo-stream action=\"refresh\"></turbo-stream>")
      captured_names([gid_stream])
    end
  end

  it "Broadcastable" do
    case_run "broadcastable_broadcasts_to_create" do
      Message.create!({"body" => "m1"})
      captured(["entries"])
    end
    case_run "broadcastable_broadcasts_to_update" do
      m = Message.first.not_nil!
      m.update!({"body" => "m2"})
      captured(["entries"])
    end
    case_run "broadcastable_broadcasts_to_destroy" do
      m = Message.first.not_nil!
      m.destroy
      captured(["entries"])
    end
    post = Post.first.not_nil!
    case_run "broadcastable_append_default_target_partial" do
      post.broadcast_append_to([:entries])
      captured(["entries"])
    end
    case_run "broadcastable_replace_to_target" do
      post.broadcast_replace_to([:entries], target: "special", html: "<p>r</p>")
      captured(["entries"])
    end
    case_run "broadcastable_remove_no_streamables" do
      post.broadcast_remove
      captured([post.to_gid_param])
    end
    case_run "broadcastable_refresh_to" do
      post.broadcast_refresh_to([:entries])
      captured(["entries"])
    end
    case_run "broadcastable_suppressing" do
      Post.suppressing_turbo_broadcasts do
        post.broadcast_remove
      end
      captured([post.to_gid_param])
    end
    case_run "broadcastable_update_later_to" do
      post.broadcast_update_later_to([:entries], target: "post_1",
        partial: "posts/post", locals: {"post" => post})
      captured(["entries"])
    end
  end

  it "HTTP format.turbo_stream" do
    case_run "http_create_turbo_stream" do
      status, ct, _, body = http_post("create", "text/vnd.turbo-stream.html, text/html;q=0.1")
      {status, ct, body.not_nil!.split("\r\n\r\n", 2)[1]? || ""}
    end
    case_run "http_create_html_fallback" do
      status, ct, location, _ = http_post("create", "text/html")
      {status, ct, location}
    end
  end
end
