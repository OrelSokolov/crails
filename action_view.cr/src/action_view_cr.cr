require "active_support_cr"

module ActionView
  VERSION = "0.1.0"

  # Helpers mixed into controllers, hence available in ECR templates.
  # Iteration 0 slice: HTML escaping only; tag/text/number/url helpers
  # come with the full action_view port (../PLAN.md).
  module Helpers
    # ECR does not escape `<%= %>` output (unlike Rails ERB), so
    # templates must wrap user-provided data in `h(...)`.
    def h(value) : String
      HTML.escape(value.to_s)
    end

    def html_escape(value : String) : String
      HTML.escape(value)
    end
  end
end
