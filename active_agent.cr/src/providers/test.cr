# TestProvider — deterministic, network-free provider for specs and
# the console: the whole agent loop (real tools, scripted provider)
# runs without sockets ("чистая логика тестируется без сокетов").
#
#   provider = ActiveAgent::Providers::Test.script do
#     tool_call "customer_search", %({"phone":"+79001234567"})
#     text "Заказ 4311 в доставке"
#   end
#   run = SupportAgent.ask("Где заказ?", provider: provider)
#
# Records every ProviderRequest it saw (assert multimodal parts, tool
# results in history, etc.).

module ActiveAgent
  module Providers
    class Test
      include Provider
      include StreamingProvider

      getter requests = [] of ProviderRequest

      @queue = [] of ProviderResponse

      def self.script(&) : self
        provider = new
        with provider yield
        provider
      end

      # Queue a turn where the "model" asks for a tool.
      def tool_call(name : String, arguments : String,
                    id : String = "call_#{rand(1000)}",
                    usage : Usage = Usage.new) : Nil
        @queue << ProviderResponse.new(nil,
          [ToolCall.new(id, name, arguments)], usage)
      end

      # Queue a plain-text turn (the "model's" final answer).
      def text(body : String, usage : Usage = Usage.new) : Nil
        @queue << ProviderResponse.new(body, [] of ToolCall, usage)
      end

      def chat(request : ProviderRequest) : ProviderResponse
        @requests << request
        @queue.shift? || raise(
          "Test script exhausted after #{@requests.size} requests")
      end

      # Streaming works the same, emitting the final text as one chunk
      # (loop mechanics are covered elsewhere; deltas are provider detail).
      def stream_chat(request : ProviderRequest, & : String -> Nil) : ProviderResponse
        response = chat(request)
        if body = response.text
          yield body
        end
        response
      end
    end
  end
end
