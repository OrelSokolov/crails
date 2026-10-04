# ActiveAgent — AI agents for business applications: agent = an
# augmented-LLM loop calling typed tools over the app's own data.
# Design-from-scratch (Iteration 17); see PLAN.md and root PLAN.md.

require "json"
require "http"
require "openssl/hmac"

require "active_support_cr"

require "./provider"
require "./tool"
require "./run"
require "./providers/openai_compatible"
require "./providers/built_in"
require "./providers/test"
require "./base"

module ActiveAgent
  VERSION = "0.1.0"
end
