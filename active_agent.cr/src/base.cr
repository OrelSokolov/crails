# ActiveAgent::Base — the agent class. Declaration DSL + the loop
# (the framework's heart):
#
#   class SupportAgent < ActiveAgent::Base
#     provider :zai, model: "glm-4.6"          # :openai | :kimi | :deepseek |
#     system "Ты оператор CRM..."               # :lmstudio | :vllm | :ollama | :test
#     tools CustomerSearch, CreateDeal
#     max_steps 12
#   end
#
#   run = SupportAgent.ask("Где мой заказ 4311?")
#   run.output  # => "Заказ 4311 в доставке"
#
# The loop: messages → provider.chat → tool_calls? → execute typed tools
# in-process (models/jobs directly reachable) → append results → repeat
# until the model answers or max_steps is hit. Every turn is instrumented
# (ActiveSupport::Notifications "agent.step") and recorded in Run#steps.

require "./provider"
require "./tool"
require "./run"
require "./providers/test"

module ActiveAgent
  class Base
    DEFAULT_MAX_STEPS = 8

    macro inherited
      {% ActiveAgent::Base::AGENTS << @type %}
    end

    AGENTS = [] of TypeNode

    # provider :openai | :zai | :kimi | :deepseek | :lmstudio | :vllm |
    #           :ollama | :test [, model: "..."]
    macro provider(name, model = nil)
      def self.__provider_name : String
        {{ name.id.stringify }}
      end

      def self.__model : String?
        {{ model }}
      end
    end

    def self.__provider_name : String
      "test"
    end

    def self.__model : String?
      nil
    end

    macro system(text)
      def self.__system_prompt : String
        {{ text }}
      end
    end

    def self.__system_prompt : String
      ""
    end

    # tools Foo, Bar — the allowlist (the agent's whole world).
    # Compile-time dispatch: metas for the wire, a case-dispatch for
    # execution (no runtime reflection, no metaclass arrays).
    macro tools(*klasses)
      def self.__tool_metas : Array(ActiveAgent::ToolMeta)
        [
          {% for k in klasses %}
            ActiveAgent::ToolMeta.new(
              {{ k.id }}.tool_name, {{ k.id }}.__description, {{ k.id }}.schema),
          {% end %}
        ] of ActiveAgent::ToolMeta
      end

      def self.__execute_tool(tc : ActiveAgent::ToolCall) : ActiveAgent::ToolResult
        case tc.name
        {% for k in klasses %}
        when {{ k.id }}.tool_name
          {{ k.id }}.__build(JSON.parse(tc.arguments)).call
        {% end %}
        else
          ActiveAgent::ToolResult.error("Unknown tool: #{tc.name}")
        end
      end
    end

    def self.__tool_metas : Array(ActiveAgent::ToolMeta)
      [] of ActiveAgent::ToolMeta
    end

    def self.__execute_tool(tc : ActiveAgent::ToolCall) : ActiveAgent::ToolResult
      ActiveAgent::ToolResult.error("Unknown tool: #{tc.name}")
    end

    macro max_steps(n)
      def self.__max_steps : Int32
        {{ n }}
      end
    end

    def self.__max_steps : Int32
      DEFAULT_MAX_STEPS
    end

    # Provider registry (the QueueAdapter-adapter analog).
    def self.build_provider : Provider
      model = __model
      case __provider_name
      when "openai"   then Providers::OpenAI.new(model)
      when "zai"      then Providers::ZAI.new(model)
      when "kimi"     then Providers::Kimi.new(model)
      when "deepseek" then Providers::DeepSeek.new(model)
      when "lmstudio" then Providers::LMStudio.new(model)
      when "vllm"     then Providers::VLLM.new(model)
      when "ollama"   then Providers::Ollama.new(model)
      when "test"     then Providers::Test.new
      else
        raise ArgumentError.new("Unknown provider: #{__provider_name} " \
                                 "(anthropic — following iteration)")
      end
    end

    # --- the loop ------------------------------------------------------------
    #
    # input: String or a multimodal Message (Message.user(text, images)).
    # provider: injectable (Providers::Test in specs — explicit, no hidden
    #           globals).
    # stream: Proc(String, Nil) — text deltas as they are generated; the
    #         same emitter bridges to ActionBot reply.stream / SSE without
    #         any cross-shard dependency.

    def self.ask(input : String | Message,
                 provider impl : Provider? = nil,
                 stream : Proc(String, Nil)? = nil) : Run
      p = impl || build_provider

      messages = [Message.system(__system_prompt)] of Message
      messages << (input.is_a?(Message) ? input : Message.user(input))
      metas = __tool_metas

      steps = [] of Step
      usage = Usage.new
      __max_steps.times do
        request = ProviderRequest.new(messages, metas, __model)
        response = if (s = stream) && p.is_a?(StreamingProvider)
                     p.stream_chat(request) { |chunk| s.call(chunk) }
                   else
                     p.chat(request)
                   end
        usage = usage + response.usage

        ActiveSupport::Notifications.instrument(
          "agent.step",
          {"agent" => name, "tool_calls" => response.tool_calls.size,
           "tokens" => usage.input_tokens + usage.output_tokens} of String => ActiveSupport::Any
        ) { nil }

        unless response.tool_calls?
          steps << Step.new(:text, text: response.text)
          return Run.new(name, response.text, :completed, steps, usage)
        end

        messages << Message.assistant(response.text, response.tool_calls)
        response.tool_calls.each do |tc|
          result = execute_tool(tc)
          steps << Step.new(:tool_call, tool_name: tc.name,
                            arguments: tc.arguments, result: result)
          messages << Message.tool_result(tc.id, tc.name, result.content)
        end
      end

      Run.new(name, steps.last?.try(&.text), :max_steps, steps, usage)
    end

    # Execute one tool call via the compile-time dispatch: parse JSON
    # args into compile-time types, run the tool's own code, never let
    # tool errors escape the loop — the model sees the error and can
    # correct itself.
    def self.execute_tool(tc : ToolCall) : ToolResult
      __execute_tool(tc)
    rescue e : Exception
      ToolResult.error("#{e.class}: #{e.message}")
    end
  end
end
