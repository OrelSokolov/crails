# DebugExceptions port spec: the development HTML error pages rendered
# by Middleware::ShowExceptions (src/debug_exceptions.cr), mirroring the
# Rails 8.1 dev pages —
#   * Routing Error: "No route matches [GET] \"/path\"", the routes
#     table (Helper / HTTP Verb / Path / Controller#Action / Source
#     Location) with a search filter;
#   * internal error: exception class/message, Application/Framework/
#     Full Trace tabs, request parameters (route + query + body) and the
#     raw request body.
# Test/production keep the bare responses (static 404 page, plain-text
# 500) — asserted here by flipping CRails.env, since the spec process
# defaults to development.

require "spec"
require "../src/railties_cr"

class DebugBoomController < ActionController::Base
  def show
    raise RuntimeError.new("kaboom")
  end

  def echo
    render plain: "ok"
  end
end

DEBUG_APP = CRails::Application.new.tap do |app|
  app.routes.draw do
    root "debug_boom#show"
    get "/echo", to: "debug_boom#echo", as: "echo"
    get "/boom/:id", to: "debug_boom#show", as: "boom"
    post "/boom/:id", to: "debug_boom#show"
    resource :session, controller: "debug_boom"
    resources :notes, only: [:index, :show]
  end
end

DEBUG_RUN = ActionDispatch::IntegrationSession.new(DEBUG_APP)

describe "debug exceptions pages (rails 8.1 dev oracle)" do
  it "routing error page: message + routes table with source location" do
    DEBUG_RUN.get "/session/new213132"
    resp = DEBUG_RUN.response.not_nil!
    resp.status_code.should eq 404
    resp.content_type.not_nil!.should start_with "text/html"
    body = resp.body
    body.should contain "Routing Error"
    # Rails message format, verbatim: No route matches [GET] "/path"
    # (quotes are HTML-escaped on the page)
    body.should contain %(No route matches [GET] &quot;/session/new213132&quot;)
    body.should contain "CRails.root: #{CRails.root}"
    # Routes table: header columns and priority note
    body.should contain "Routes"
    body.should contain "match in priority from top to bottom"
    body.should contain "Helper (Path / Url)"
    body.should contain "HTTP Verb"
    body.should contain "Controller#Action"
    body.should contain "Source Location"
    # Drawn routes: helper names, verbs, patterns, controller#action
    body.should contain "root_path"
    body.should contain "new_session_path"
    body.should contain "notes_path"
    body.should contain "/notes/:id"
    body.should contain "debug_boom#echo"
    # Source location — the file:line that drew the route (this spec)
    body.should contain "#{__DIR__}/debug_exceptions_spec.cr:"
    # Search filter input present
    body.should contain %(type="search")
  end

  it "internal error page: exception, params, request body" do
    DEBUG_RUN.post "/boom/7", params: {"post" => {"title" => "T1"}}, headers: {"X-Test" => "1"}
    resp = DEBUG_RUN.response.not_nil!
    resp.status_code.should eq 500
    resp.content_type.not_nil!.should start_with "text/html"
    body = resp.body
    body.should contain "RuntimeError"
    body.should contain "kaboom"
    # Trace tabs, as the Rails page
    body.should contain "Application Trace"
    body.should contain "Framework Trace"
    body.should contain "Full Trace"
    # The raising frame is app code — this spec file shows in the trace
    body.should contain "debug_exceptions_spec.cr:"
    # Parameters: controller/action + route param + form body params
    body.should contain "<code>controller</code>"
    body.should contain "<code>action</code>"
    body.should contain "<code>id</code>"
    body.should contain "<code>7</code>"
    body.should contain "post[title]"
    body.should contain "T1"
    # Raw request body card with the form encoding
    body.should contain "Request body"
    body.should contain "post%5Btitle%5D=T1"
  end

  it "json body is shown parsed and raw" do
    DEBUG_RUN.post "/boom/9", json: %({"post":{"title":"J"}})
    body = DEBUG_RUN.response.not_nil!.body
    body.should contain %({&quot;post&quot;:{&quot;title&quot;:&quot;J&quot;}})
    body.should contain "Request body"
  end

  it "test/production keep the bare responses" do
    before = CRails.env
    CRails.env = CRails::Env::Production
    begin
      DEBUG_RUN.get "/nope"
      resp = DEBUG_RUN.response.not_nil!
      resp.status_code.should eq 404
      resp.body.should contain "404 Not Found"
      resp.body.should_not contain "Routing Error"

      DEBUG_RUN.get "/boom/1"
      resp = DEBUG_RUN.response.not_nil!
      resp.status_code.should eq 500
      resp.content_type.not_nil!.should start_with "text/plain"
      resp.body.should eq "500 Internal Server Error"
    ensure
      CRails.env = before
    end
  end
end
