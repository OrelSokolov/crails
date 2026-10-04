# Run / Step — the audit trail of an agent's work. Every step the model
# took is visible: what it said, which tool it called with what
# arguments, and what came back. Transparency over magic (research
# conclusion: "explicitly show the agent's planning steps").

module ActiveAgent
  class Step
    getter kind : Symbol    # :text | :tool_call
    getter text : String?   # assistant text of the turn
    getter tool_name : String?
    getter arguments : String?
    getter result : ToolResult?

    def initialize(@kind, @text = nil, @tool_name = nil,
                   @arguments = nil, @result = nil)
    end

    def to_s : String
      case @kind
      when :tool_call
        "#{@tool_name}(#{@arguments}) => #{@result.try(&.ok) ? "ok" : "error"}"
      else
        @text.to_s
      end
    end
  end

  class Run
    getter agent_name : String
    getter output : String?
    getter status : Symbol # :completed | :max_steps
    getter steps : Array(Step)
    getter usage : Usage

    def initialize(@agent_name, @output, @status, @steps, @usage)
    end

    def completed? : Bool
      @status == :completed
    end

    # P2 (interrupt/resume, HITL on solid_queue) — placeholder contract.
    def interrupted? : Bool
      false
    end

    def tool_steps : Array(Step)
      @steps.select(&.kind.==(:tool_call))
    end
  end
end
