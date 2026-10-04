# Loop specs — the agent orchestration on Providers::Test (network-free,
# real tools): tool→result→final, streaming emitter, max_steps, usage
# accumulation, tool errors fed back to the model, multimodal messages
# reaching the provider, typed argument validation.

require "spec"
require "../src/active_agent_cr"

# --- fixture tools & agents -------------------------------------------------

class CustomerSearch
  include ActiveAgent::Tool
  description "Найти клиента по телефону или имени. Возвращает профиль и открытые заказы."
  input phone : String?, name : String?

  def call : ActiveAgent::ToolResult
    if phone == "+79001234567"
      ActiveAgent::ToolResult.ok(%({"name":"Олег"}))
    else
      ActiveAgent::ToolResult.error("клиент не найден")
    end
  end
end

class CreateDeal
  include ActiveAgent::Tool
  description "Создать сделку для клиента."
  input title : String, amount : Int64

  def call : ActiveAgent::ToolResult
    ActiveAgent::ToolResult.ok(%({"deal":"#{title}:#{amount}"}))
  end
end

class SupportAgent < ActiveAgent::Base
  provider :test
  system "Ты оператор CRM. Сначала найди клиента."
  tools CustomerSearch, CreateDeal
  max_steps 4
end

class PlantDoctor < ActiveAgent::Base
  provider :test
  system "Ты агроном. Определи болезнь по фото."
end

describe "ActiveAgent loop" do
  it "runs tool → result → final" do
    brain = ActiveAgent::Providers::Test.script do
      tool_call "customer_search", %({"phone":"+79001234567"}), id: "call_X1",
        usage: ActiveAgent::Usage.new(110, 18)
      text "Заказ 4311 в доставке, придёт завтра.",
        usage: ActiveAgent::Usage.new(240, 12)
    end
    run = SupportAgent.ask("Где мой заказ 4311?", provider: brain)

    run.completed?.should be_true
    run.output.should eq "Заказ 4311 в доставке, придёт завтра."
    run.steps.size.should eq 2
    run.tool_steps.size.should eq 1
    run.tool_steps.first.tool_name.should eq "customer_search"
    run.tool_steps.first.result.not_nil!.ok.should be_true
    run.usage.input_tokens.should eq 350
    run.usage.output_tokens.should eq 30
    run.interrupted?.should be_false

    # the second brain request carries the full history: assistant
    # tool_calls + tool result
    msgs = brain.requests[1].messages
    msgs[2].role.should eq :assistant
    msgs[2].tool_calls.first.name.should eq "customer_search"
    msgs[3].role.should eq :tool
    msgs[3].tool_call_id.should eq "call_X1"
    msgs[3].text.should eq %({"name":"Олег"})
  end

  it "feeds tool errors back to the model instead of crashing" do
    brain = ActiveAgent::Providers::Test.script do
      tool_call "customer_search", %({"phone":"+79990000000"})
      text "Такого клиента нет в базе."
    end
    run = SupportAgent.ask("найди клиента", provider: brain)
    run.completed?.should be_true
    run.tool_steps.first.result.not_nil!.ok.should be_false
    # the model saw the error content
    brain.requests[1].messages[3].text.should eq "клиент не найден"
  end

  it "executes unknown tools as errors the model can see" do
    brain = ActiveAgent::Providers::Test.script do
      tool_call "nope_tool", %({})
      text "ок"
    end
    run = SupportAgent.ask("x", provider: brain)
    run.tool_steps.first.result.not_nil!.content.should contain "Unknown tool"
  end

  it "validates required typed arguments before tool code runs" do
    brain = ActiveAgent::Providers::Test.script do
      tool_call "create_deal", %({"title":"Обновление"}) # amount missing
      text "ок"
    end
    run = SupportAgent.ask("создай сделку", provider: brain)
    step = run.tool_steps.first
    step.result.not_nil!.ok.should be_false
    step.result.not_nil!.content.should contain "amount"
  end

  it "stops at max_steps (mandatory stopping condition)" do
    brain = ActiveAgent::Providers::Test.new
    10.times { brain.tool_call "customer_search", %({"phone":"+79001234567"}) }
    run = SupportAgent.ask("вечный цикл", provider: brain)
    run.status.should eq :max_steps
    run.completed?.should be_false
    run.steps.size.should eq SupportAgent.__max_steps
  end

  it "streams text deltas through the emitter" do
    brain = ActiveAgent::Providers::Test.script do
      text "Генерация по чанкам"
    end
    chunks = [] of String
    run = SupportAgent.ask("расскажи", provider: brain,
      stream: ->(c : String) { chunks << c })
    chunks.should eq ["Генерация по чанкам"]
    run.output.should eq "Генерация по чанкам"
  end

  it "passes multimodal messages (text + images) to the brain" do
    brain = ActiveAgent::Providers::Test.script do
      text "Мучнистая роса."
    end
    input = ActiveAgent::Message.user("Что с листьями?",
      ["https://example.com/leaf.jpg"])
    run = PlantDoctor.ask(input, provider: brain)
    run.output.should eq "Мучнистая роса."

    user_msg = brain.requests.first.messages[1]
    user_msg.role.should eq :user
    user_msg.images.should eq ["https://example.com/leaf.jpg"]
    user_msg.text.should eq "Что с листьями?"
  end
end

class NoDescTool
  include ActiveAgent::Tool
  input x : String?
end

describe "ActiveAgent::Tool contract" do
  it "builds the JSON Schema at compile time (function calling)" do
    CustomerSearch.schema.to_json.should eq(
      %({"type":"object","properties":{"phone":{"type":"string"},"name":{"type":"string"}},"additionalProperties":false}))
    CreateDeal.schema.to_json.should eq(
      %({"type":"object","properties":{"title":{"type":"string"},"amount":{"type":"integer"}},"required":["title","amount"],"additionalProperties":false}))
  end

  it "requires a description (ACI)" do
    expect_raises(NotImplementedError) { NoDescTool.__description }
  end

  it "names tools in snake_case on the wire" do
    CustomerSearch.tool_name.should eq "customer_search"
  end
end
