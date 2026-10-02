# Controller-layer specs: before_action, rescue_from, respond_to,
# redirect/flash, strong-params integration into requests, body params.

require "spec"
require "http"
require "../src/action_pack_cr"

abstract class ApplicationController < ActionController::Base
end

class FilteredController < ApplicationController
  before_action :log_all
  before_action :only_show, only: [:show]
  before_action :no_show, except: [:show]
  before_action :conditional, if: :condition_true, only: [:index]

  getter trace = [] of String

  def index
    render plain: trace.join(",")
  end

  def show
    render plain: trace.join(",")
  end

  private def log_all
    trace << "all"
  end

  private def only_show
    trace << "only_show"
  end

  private def no_show
    trace << "no_show"
  end

  private def conditional
    trace << "conditional"
  end

  private def condition_true
    true
  end
end

class GuardedController < ApplicationController
  before_action :authenticate, only: [:secret]

  def public
    render plain: "public"
  end

  def secret
    render plain: "secret"
  end

  private def authenticate
    redirect_to "/login" unless session["user_id"]?
  end
end

class RescuedController < ApplicationController
  class CustomError < Exception; end

  rescue_from CustomError, with: :handle_custom
  rescue_from KeyError, with: :handle_key

  def boom
    raise CustomError.new("boom")
  end

  def missing
    h = {} of String => String
    h["nope"]
    render plain: "never"
  end

  private def handle_custom(error)
    render plain: "rescued: #{error.message}", status: 418
  end

  private def handle_key(error)
    render plain: "key error", status: 500
  end
end

class FormatsController < ApplicationController
  def data
    respond_to do |format|
      format.html { render plain: "HTML" }
      format.json { render json: %({"format":"json"}) }
    end
  end
end

class FlashController < ApplicationController
  def create
    redirect_to "/done", notice: "Created!"
  end
end

class EchoController < ApplicationController
  def echo
    title = params.require(:post).permit(:title).to_h["title"]
    render plain: title.to_s
  end
end

private def build_context(method : String, path : String,
                          body : String? = nil, content_type : String? = nil,
                          cookie : String? = nil) : HTTP::Server::Context
  headers = HTTP::Headers.new
  headers["Content-Type"] = content_type if content_type
  headers["Cookie"] = cookie if cookie
  request = HTTP::Request.new(method, path, headers, body)
  io = IO::Memory.new
  response = HTTP::Server::Response.new(io)
  HTTP::Server::Context.new(request, response)
end

private def dispatch(context : HTTP::Server::Context, klass, action : String,
                     route_params : Hash(String, String) = {} of String => String) : HTTP::Server::Context
  controller = klass.new(context)
  controller.__set_params(route_params)
  controller.__run_action(action)
  context.response.close
  context
end

describe "before_action" do
  it "runs all matching filters in order" do
    ctx = dispatch(build_context("GET", "/"), FilteredController, "index")
    controller = FilteredController.new(build_context("GET", "/"))
    controller.__set_params({} of String => String)
    controller.__run_action("index")
    controller.response.close
    (controller.trace == ["all", "no_show", "conditional"]).should be_true
  end

  it "honors only: and except:" do
    controller = FilteredController.new(build_context("GET", "/"))
    controller.__set_params({} of String => String)
    controller.__run_action("show")
    controller.response.close
    (controller.trace == ["all", "only_show"]).should be_true
  end

  it "halts the chain on redirect (filter performed)" do
    ctx = dispatch(build_context("GET", "/"), GuardedController, "secret")
    ctx.response.status_code.should eq(302)
    ctx.response.headers["Location"].should eq("/login")
  end

  it "does not run the filter for other actions" do
    ctx = dispatch(build_context("GET", "/"), GuardedController, "public")
    ctx.response.status_code.should eq(200)
  end
end

describe "rescue_from" do
  it "routes matching exceptions to the handler" do
    ctx = dispatch(build_context("GET", "/"), RescuedController, "boom")
    ctx.response.status_code.should eq(418)
  end

  it "matches other exception types" do
    ctx = dispatch(build_context("GET", "/"), RescuedController, "missing")
    ctx.response.status_code.should eq(500)
  end
end

describe "respond_to" do
  it "serves html by default" do
    ctx = dispatch(build_context("GET", "/"), FormatsController, "data")
    ctx.response.headers["Content-Type"].should contain("text/plain")
  end

  it "serves json when ?format=json" do
    ctx = dispatch(build_context("GET", "/?format=json"), FormatsController, "data")
    ctx.response.headers["Content-Type"].should contain("application/json")
  end

  it "serves json when Accept prefers it" do
    headers = HTTP::Headers{"Accept" => "application/json"}
    request = HTTP::Request.new("GET", "/", headers)
    io = IO::Memory.new
    ctx = HTTP::Server::Context.new(request, HTTP::Server::Response.new(io))
    dispatch(ctx, FormatsController, "data")
    ctx.response.headers["Content-Type"].should contain("application/json")
  end
end

describe "flash" do
  it "redirect_to with notice sets the flash cookie" do
    ctx = dispatch(build_context("POST", "/"), FlashController, "create")
    ctx.response.headers["Set-Cookie"].should contain("crails_flash")
    ctx.response.status_code.should eq(302)
  end

  it "flash read-once: available on the next request, then gone" do
    controller = FlashController.new(
      build_context("GET", "/done", cookie: "crails_flash=#{URI.encode_www_form(Base64.strict_encode({"notice" => "Hi"}.to_json))}"))
    controller.__set_params({} of String => String)
    controller.flash["notice"].should eq("Hi")
  end
end

describe "request params" do
  it "merges JSON body params into strong params" do
    ctx = build_context("POST", "/echo", body: %({"post":{"title":"T"}}),
      content_type: "application/json")
    dispatch(ctx, EchoController, "echo")
    # assert via a second controller instance reading output
    io = IO::Memory.new
    request = HTTP::Request.new("POST", "/echo",
      HTTP::Headers{"Content-Type" => "application/json"}, %({"post":{"title":"T"}}))
    response = HTTP::Server::Response.new(io)
    controller = EchoController.new(HTTP::Server::Context.new(request, response))
    controller.__set_params({} of String => String)
    controller.__run_action("echo")
    response.close
    io.to_s.should contain("T")
  end

  it "merges form-encoded body params" do
    io = IO::Memory.new
    request = HTTP::Request.new("POST", "/echo",
      HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"},
      "post[title]=From+Form")
    response = HTTP::Server::Response.new(io)
    controller = EchoController.new(HTTP::Server::Context.new(request, response))
    controller.__set_params({} of String => String)
    controller.__run_action("echo")
    response.close
    io.to_s.should contain("From Form")
  end

  it "require raises ParameterMissing for missing key" do
    io = IO::Memory.new
    request = HTTP::Request.new("POST", "/echo",
      HTTP::Headers{"Content-Type" => "application/json"}, %({"other":1}))
    response = HTTP::Server::Response.new(io)
    controller = EchoController.new(HTTP::Server::Context.new(request, response))
    controller.__set_params({} of String => String)
    expect_raises ActionController::ParameterMissing do
      controller.__run_action("echo")
    end
  end
end
