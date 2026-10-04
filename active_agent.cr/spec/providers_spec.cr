# Provider registry specs — every built-in provider builds, hits its
# own endpoint config, and speaks the same oracle-locked wire (they
# share the OpenAICompatible engine; differences are env/defaults/
# quirks). Live ZAI smoke runs only when ZAI_API_KEY is set.

require "spec"
require "../src/active_agent_cr"

def fake_provider_server(&handler : HTTP::Server::Context -> Nil) : HTTP::Server
  server = HTTP::Server.new(&handler)
  server.bind_unused_port
  spawn { server.listen }
  20.times { sleep(10.milliseconds); break if server.listening? }
  server
end

def fake_base(server : HTTP::Server) : String
  addr = server.addresses.first.as?(Socket::IPAddress).not_nil!
  "http://#{addr}"
end

# Compile-time declared agents for registry checks
class RegistryZaiAgent < ActiveAgent::Base
  provider :zai
end

class RegistryKimiAgent < ActiveAgent::Base
  provider :kimi, model: "kimi-k2-0905-preview"
end

class RegistryDeepSeekAgent < ActiveAgent::Base
  provider :deepseek
end

class RegistryLMStudioAgent < ActiveAgent::Base
  provider :lmstudio
end

class RegistryVLLMAgent < ActiveAgent::Base
  provider :vllm
end

class RegistryOllamaAgent < ActiveAgent::Base
  provider :ollama
end

describe "provider registry" do
  it "resolves each DSL name to its provider class" do
    RegistryZaiAgent.build_provider.should be_a(ActiveAgent::Providers::ZAI)
    RegistryKimiAgent.build_provider.should be_a(ActiveAgent::Providers::Kimi)
    RegistryDeepSeekAgent.build_provider.should be_a(ActiveAgent::Providers::DeepSeek)
    RegistryLMStudioAgent.build_provider.should be_a(ActiveAgent::Providers::LMStudio)
    RegistryVLLMAgent.build_provider.should be_a(ActiveAgent::Providers::VLLM)
    RegistryOllamaAgent.build_provider.should be_a(ActiveAgent::Providers::Ollama)
  end

  it "zai/kimi/deepseek hit their configured endpoints with the shared wire" do
    final = File.read("#{__DIR__}/../oracle/fixtures/openai/04_response_final.json")
    requests = [] of String
    server = fake_provider_server do |context|
      body = context.request.body.try(&.gets_to_end) || ""
      requests << context.request.path.not_nil!
      context.response.content_type = "application/json"
      context.response.print(final)
    end
    base = fake_base(server)

    # Snapshot env (the live ZAI smoke below reads the real key) and
    # restore afterwards — never delete what was there before.
    saved = {} of String => String?
    {"ZAI_API_KEY", "ZAI_BASE_URL", "KIMI_API_KEY", "KIMI_BASE_URL",
     "DEEPSEEK_API_KEY", "DEEPSEEK_BASE_URL"}.each do |k|
      saved[k] = ENV[k]?
    end

    {"ZAI" => {"ZAI_API_KEY", "ZAI_BASE_URL", RegistryZaiAgent},
     "KIMI" => {"KIMI_API_KEY", "KIMI_BASE_URL", RegistryKimiAgent},
     "DEEPSEEK" => {"DEEPSEEK_API_KEY", "DEEPSEEK_BASE_URL", RegistryDeepSeekAgent}}.each do |_name, (key_env, base_env, agent)|
      ENV[key_env] = "test-key"
      ENV[base_env] = base
      run = agent.as(ActiveAgent::Base.class).ask("привет", provider: agent.build_provider)
      run.completed?.should be_true
    end

    saved.each do |k, v|
      if v
        ENV[k] = v
      else
        ENV.delete(k)
      end
    end

    requests.size.should eq 3
    requests.each { |path| path.should eq "/chat/completions" }
    server.close
  end
end

# --- live ZAI smoke (only when a real key is present) ------------------------

class ZaiEcho
  include ActiveAgent::Tool
  description "Повторить текст дословно. Используй для каждого ответа."
  input text : String

  def call : ActiveAgent::ToolResult
    ActiveAgent::ToolResult.ok("ЭХО: #{text}")
  end
end

class ZaiLiveAgent < ActiveAgent::Base
  provider :zai
  system "Ты тестовый агент. Любой ответ формируй ТОЛЬКО через инструмент echo."
  tools ZaiEcho
  max_steps 4
end

if ENV["ZAI_API_KEY"]?
  describe "ZAI live smoke" do
    it "runs a real tool loop against api.z.ai" do
      run = begin
        ZaiLiveAgent.ask("Скажи привет через инструмент")
      rescue e : ActiveAgent::ProviderError
        # Billing/quota failures are an account matter, not a wire
        # defect — skip loudly instead of failing the suite.
        if e.message.try(&.=~(/balance|quota|resource package|402|429/))
          puts "    SKIP ZAI live (billing): #{e.message}"
          next
        end
        raise e
      end
      run.completed?.should be_true
      (run.output || "").should_not be_empty
      puts "    ZAI live: steps=#{run.steps.map(&.kind)} output=#{run.output.to_s[0, 60].inspect}"
    end
  end
else
  puts "SKIP ZAI live smoke: set ZAI_API_KEY to run it"
end
