# Provider — the LLM provider port (the QueueAdapter analog): any
# model behind one interface. Messages are multimodal from day one
# (content-parts: text + images) — the wire format the whole industry
# (OpenAI/Anthropic/ZAI/Kimi/DeepSeek...) speaks.
#
# Naming: Provider, not Brain — these are provider adapters with their
# own implementations and behavior quirks (see Providers::OpenAICompatible
# for the shared chat-completions engine and the per-provider classes).

module ActiveAgent
  class ToolCall
    getter id : String
    getter name : String
    getter arguments : String # raw JSON string from the wire

    def initialize(@id, @name, @arguments)
    end
  end

  class Usage
    getter input_tokens : Int64
    getter output_tokens : Int64

    def initialize(@input_tokens = 0_i64, @output_tokens = 0_i64)
    end

    def +(other : Usage) : Usage
      Usage.new(@input_tokens + other.input_tokens,
                @output_tokens + other.output_tokens)
    end
  end

  # Multimodal conversation message. roles:
  #   :system    — instructions
  #   :user      — input (text + images)
  #   :assistant — model turn (text and/or tool_calls)
  #   :tool      — tool result for a tool_call_id
  class Message
    getter role : Symbol
    getter text : String?
    getter images : Array(String) # URLs or data-URIs
    getter tool_calls : Array(ToolCall)
    getter tool_call_id : String?
    getter name : String?

    def initialize(@role, @text = nil, @images = [] of String,
                   @tool_calls = [] of ToolCall, @tool_call_id = nil,
                   @name = nil)
    end

    def self.system(text : String) : Message
      new(:system, text)
    end

    def self.user(text : String, images : Array(String) = [] of String) : Message
      new(:user, text, images)
    end

    def self.assistant(text : String?, tool_calls : Array(ToolCall) = [] of ToolCall) : Message
      new(:assistant, text, [] of String, tool_calls)
    end

    def self.tool_result(tool_call_id : String, name : String, content : String) : Message
      new(:tool, content, [] of String, [] of ToolCall, tool_call_id, name)
    end
  end

  # Compile-time tool metadata the provider serializes for function calling.
  class ToolMeta
    getter name : String
    getter description : String
    getter schema : JSON::Any

    def initialize(@name, @description, @schema)
    end
  end

  class ProviderRequest
    getter model : String?
    getter messages : Array(Message)
    getter tools : Array(ToolMeta)
    getter max_tokens : Int32?

    def initialize(@messages, @tools = [] of ToolMeta, @model = nil,
                   @max_tokens = nil)
    end
  end

  class ProviderResponse
    getter text : String?
    getter tool_calls : Array(ToolCall)
    getter usage : Usage

    def initialize(@text = nil, @tool_calls = [] of ToolCall,
                   @usage = Usage.new)
    end

    def tool_calls? : Bool
      !@tool_calls.empty?
    end
  end

  # The port itself: frozen, small (ISP). Implementations:
  # OpenAICompatible engine + OpenAI/ZAI/Kimi/DeepSeek/LMStudio/VLLM/
  # Ollama, Anthropic (native), Test.
  module Provider
    abstract def chat(request : ProviderRequest) : ProviderResponse
  end

  # A provider API error (non-2xx or error-shaped body): carries the
  # status and the API's own message — never a bare KeyError.
  class ProviderError < Exception
    getter status : HTTP::Status?

    def initialize(message, @status = nil)
      super(message)
    end
  end

  # Optional capability — streaming generation. Chunks are text deltas;
  # tool_calls still arrive via the returned ProviderResponse.
  module StreamingProvider
    include Provider

    abstract def stream_chat(request : ProviderRequest, & : String -> Nil) : ProviderResponse
  end
end
