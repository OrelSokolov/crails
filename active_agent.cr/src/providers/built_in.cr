# Built-in providers — thin per-provider configs over the shared
# OpenAICompatible engine: env vars, endpoints, model defaults, quirks.
# Same wire protocol, different homes and behaviors.

module ActiveAgent
  module Providers
    # OpenAI proper.
    class OpenAI < OpenAICompatible
      def initialize(model : String? = nil)
        super(ENV["OPENAI_API_KEY"]? || "",
              ENV["OPENAI_BASE_URL"]? || "https://api.openai.com/v1",
              model || "gpt-4o")
      end
    end

    # ZAI (Zhipu GLM) — OpenAI-compatible endpoint.
    class ZAI < OpenAICompatible
      def initialize(model : String? = nil)
        super(ENV["ZAI_API_KEY"]? || "",
              ENV["ZAI_BASE_URL"]? || "https://api.z.ai/api/paas/v4",
              model || "glm-4.6")
      end
    end

    # Kimi (Moonshot) — agentic flagship with strong tool calling.
    class Kimi < OpenAICompatible
      def initialize(model : String? = nil)
        super(ENV["KIMI_API_KEY"]? || ENV["MOONSHOT_API_KEY"]? || "",
              ENV["KIMI_BASE_URL"]? || ENV["MOONSHOT_BASE_URL"]? || "https://api.moonshot.cn/v1",
              model || "kimi-k2-0905-preview")
      end
    end

    # DeepSeek.
    class DeepSeek < OpenAICompatible
      def initialize(model : String? = nil)
        super(ENV["DEEPSEEK_API_KEY"]? || "",
              ENV["DEEPSEEK_BASE_URL"]? || "https://api.deepseek.com/v1",
              model || "deepseek-chat")
      end
    end

    # LM Studio — local; no key, and older builds reject stream_options.
    class LMStudio < OpenAICompatible
      def initialize(model : String? = nil)
        super(ENV["LMSTUDIO_API_KEY"]? || "lm-studio",
              ENV["LMSTUDIO_BASE_URL"]? || "http://localhost:1234/v1",
              model)
      end
    end

    # vLLM — local serving; model = the served model name.
    class VLLM < OpenAICompatible
      def initialize(model : String? = nil)
        super(ENV["VLLM_API_KEY"]? || "",
              ENV["VLLM_BASE_URL"]? || "http://localhost:8000/v1",
              model)
      end
    end

    # Ollama — via its official OpenAI-compatible endpoint (native
    # /api/chat is a different wire — separate provider if ever needed).
    class Ollama < OpenAICompatible
      def initialize(model : String? = nil)
        super(ENV["OLLAMA_API_KEY"]? || "ollama",
              ENV["OLLAMA_BASE_URL"]? || "http://localhost:11434/v1",
              model)
      end
    end
  end
end
