# OpenAI integration spec — the full agent loop over HTTP against a
# fake OpenAI server (the smtp_spec pattern): ask → tool_calls → tool
# executed in-process → tool result posted back → final answer; plus
# real SSE streaming through stream_chat.

require "spec"
require "../src/active_agent_cr"

class FakeOpenAI
  getter requests = [] of {String, String} # path, body

  def initialize(&@handler : HTTP::Server::Context, String -> Nil)
    @server = HTTP::Server.new do |context|
      body = context.request.body.try(&.gets_to_end) || ""
      @requests << {context.request.path.not_nil!, body}
      @handler.call(context, body)
    end
    @server.bind_unused_port
    spawn { @server.listen }
    20.times { sleep(10.milliseconds); break if @server.listening? }
  end

  def base : String
    addr = @server.addresses.first.as?(Socket::IPAddress).not_nil!
    "http://#{addr}"
  end

  def close : Nil
    @server.close
  end
end

TOOL_CALLS_RESPONSE = File.read("#{__DIR__}/../oracle/fixtures/openai/03_response_tool_calls.json")
FINAL_RESPONSE      = File.read("#{__DIR__}/../oracle/fixtures/openai/04_response_final.json")
STREAM_BODY         = File.read("#{__DIR__}/../oracle/fixtures/openai/05_stream_chunks.txt")

# Namespaced to keep the wire name "customer_search" (tool_name is the
# last path segment) — matches the fixture responses.
module Http
  class CustomerSearch
    include ActiveAgent::Tool
    description "Найти клиента по телефону или имени. Возвращает профиль и открытые заказы."
    input phone : String?, name : String?

    def call : ActiveAgent::ToolResult
      ActiveAgent::ToolResult.ok(%({"name":"Олег"}))
    end
  end
end

class HttpAgent < ActiveAgent::Base
  provider :openai, model: "gpt-4o"
  system "Ты оператор CRM. Сначала найди клиента."
  tools Http::CustomerSearch
end

describe "OpenAI brain over HTTP" do
  it "runs ask → tool_call → tool result → final answer" do
    served = 0
    server = FakeOpenAI.new do |context, body|
      context.response.content_type = "application/json"
      served += 1
      context.response.print(served == 1 ? TOOL_CALLS_RESPONSE : FINAL_RESPONSE)
    end
    ENV["OPENAI_API_KEY"] = "sk-test"
    ENV["OPENAI_BASE_URL"] = server.base

    run = HttpAgent.ask("Где мой заказ 4311?")

    run.completed?.should be_true
    run.output.should eq "Заказ 4311 в доставке, придёт завтра."
    run.tool_steps.first.tool_name.should eq "customer_search"
    run.usage.input_tokens.should eq 350

    # request 1: tools payload; request 2: history with tool result
    server.requests.size.should eq 2
    server.requests[0][0].should eq "/chat/completions"
    server.requests[1][1].should contain(%("tool_call_id":"call_X1"))
    server.requests[1][1].should contain(%q({\"name\":\"Олег\"}))

    server.close
    ENV.delete("OPENAI_BASE_URL")
    ENV.delete("OPENAI_API_KEY")
  end

  it "streams deltas over SSE and assembles the response" do
    server = FakeOpenAI.new do |context, body|
      context.response.content_type = "text/event-stream"
      context.response.print(STREAM_BODY)
    end
    ENV["OPENAI_API_KEY"] = "sk-test"
    ENV["OPENAI_BASE_URL"] = server.base

    prov = ActiveAgent::Providers::OpenAI.new
    chunks = [] of String
    request = ActiveAgent::ProviderRequest.new(
      [ActiveAgent::Message.user("краткий прогноз")])
    response = prov.stream_chat(request) { |c| chunks << c }

    chunks.should eq ["Прив", "ет завтра."]
    response.text.should eq "Привет завтра."
    response.usage.input_tokens.should eq 50
    server.requests.first[1].should contain(%("stream":true))

    server.close
    ENV.delete("OPENAI_BASE_URL")
    ENV.delete("OPENAI_API_KEY")
  end
end
