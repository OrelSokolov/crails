# OpenAICompatible — the shared chat-completions engine. Most of the
# market speaks this wire format: OpenAI, ZAI (Zhipu GLM), Kimi
# (Moonshot), DeepSeek, LM Studio, vLLM, Ollama's compatibility
# endpoint. Concrete providers subclass with their own env vars,
# endpoints, model defaults — and quirks (e.g. `stream_options`
# support). Wire shapes are oracle-locked byte-exact
# (oracle/fixtures/openai/*).

module ActiveAgent
  module Providers
    class OpenAICompatible
      include Provider
      include StreamingProvider

      def initialize(@api_key : String = "", @base_url : String = "",
                     @default_model : String? = nil,
                     @stream_options : Bool = true)
      end

      # --- payload builders (pure — oracle-compared byte for byte) ------

      def build_payload(request : ProviderRequest) : String
        JSON.build do |j|
          j.object do
            j.field "model", request.model || @default_model || "gpt-4o"
            j.field "messages" do
              j.array do
                request.messages.each { |m| write_message(j, m) }
              end
            end
            unless request.tools.empty?
              j.field "tools" do
                j.array do
                  request.tools.each do |t|
                    j.object do
                      j.field "type", "function"
                      j.field "function" do
                        j.object do
                          j.field "name", t.name
                          j.field "description", t.description
                          j.field "parameters", t.schema
                        end
                      end
                    end
                  end
                end
              end
              j.field "tool_choice", "auto"
            end
          end
        end
      end

      private def write_message(j : JSON::Builder, m : Message) : Nil
        j.object do
          case m.role
          when :system
            j.field "role", "system"
            j.field "content", m.text.to_s
          when :user
            j.field "role", "user"
            if m.images.empty?
              j.field "content", m.text.to_s
            else
              # Multimodal content parts: text + image_url.
              j.field "content" do
                j.array do
                  j.object do
                    j.field "type", "text"
                    j.field "text", m.text.to_s
                  end
                  m.images.each do |url|
                    j.object do
                      j.field "type", "image_url"
                      j.field "image_url" do
                        j.object do
                          j.field "url", url
                        end
                      end
                    end
                  end
                end
              end
            end
          when :assistant
            j.field "role", "assistant"
            j.field "content", m.text # null when tool_calls-only (wire shape)
            unless m.tool_calls.empty?
              j.field "tool_calls" do
                j.array do
                  m.tool_calls.each do |tc|
                    j.object do
                      j.field "id", tc.id
                      j.field "type", "function"
                      j.field "function" do
                        j.object do
                          j.field "name", tc.name
                          j.field "arguments", tc.arguments
                        end
                      end
                    end
                  end
                end
              end
            end
          when :tool
            j.field "role", "tool"
            j.field "tool_call_id", m.tool_call_id.to_s
            j.field "content", m.text.to_s
          end
        end
      end

      def build_stream_payload(request : ProviderRequest) : String
        base = JSON.parse(build_payload(request)).as_h
        base["stream"] = JSON::Any.new(true)
        if @stream_options
          base["stream_options"] = JSON::Any.new(
            {"include_usage" => JSON::Any.new(true)} of String => JSON::Any)
        end
        base.to_json
      end

      # --- response parsing ------------------------------------------------

      def parse_response(body : String) : ProviderResponse
        parse_message(JSON.parse(body))
      end

      def parse_message(payload : JSON::Any) : ProviderResponse
        unless choices = payload["choices"]?.try(&.as_a?)
          # error-shaped body: {"error":{"code":"...","message":"..."}}
          msg = payload["error"]?.try(&.["message"]?).try(&.as_s?) || payload.to_json[0, 300]
          raise ProviderError.new("provider error: #{msg}")
        end
        choice = choices.first
        message = choice["message"]
        text = message["content"]?.try(&.as_s?)

        tool_calls = [] of ToolCall
        if tcs = message["tool_calls"]?.try(&.as_a?)
          tcs.each do |tc|
            fn = tc["function"]
            tool_calls << ToolCall.new(
              tc["id"]?.try(&.as_s?) || "",
              fn["name"]?.try(&.as_s?) || "",
              fn["arguments"]?.try(&.as_s?) || "{}")
          end
        end

        usage = parse_usage(payload["usage"]?)
        ProviderResponse.new(text, tool_calls, usage)
      end

      def parse_usage(u : JSON::Any?) : Usage
        return Usage.new unless u
        in_tok = u["prompt_tokens"]?.try(&.as_i?) || 0
        out_tok = u["completion_tokens"]?.try(&.as_i?) || 0
        Usage.new(in_tok.to_i64, out_tok.to_i64)
      end

      def ensure_ok(response : HTTP::Client::Response) : Nil
        return if response.status.ok?
        body = response.body[0, 300]
        raise ProviderError.new(
          "provider HTTP #{response.status}: #{body}", response.status)
      end

      # --- Provider port -----------------------------------------------------

      def chat(request : ProviderRequest) : ProviderResponse
        response = HTTP::Client.post("#{@base_url}/chat/completions",
          headers: HTTP::Headers{
            "Content-Type"  => "application/json",
            "Authorization" => "Bearer #{@api_key}",
          },
          body: build_payload(request))
        ensure_ok(response)
        parse_response(response.body)
      end

      def stream_chat(request : ProviderRequest, & : String -> Nil) : ProviderResponse
        response = HTTP::Client.post("#{@base_url}/chat/completions",
          headers: HTTP::Headers{
            "Content-Type"  => "application/json",
            "Authorization" => "Bearer #{@api_key}",
            "Accept"        => "text/event-stream",
          },
          body: build_stream_payload(request))
        ensure_ok(response)

        text = String::Builder.new
        tool_calls = {} of Int32 => {String?, String::Builder} # index → {name?, args}
        usage = Usage.new

        response.body.each_line do |line|
          next unless line.starts_with?("data: ")
          data = line[6..]
          break if data == "[DONE]"
          chunk = JSON.parse(data)
          usage = parse_usage(chunk["usage"]?) if chunk["usage"]?
          next unless choices = chunk["choices"]?.try(&.as_a?)
          next if choices.empty?
          delta = choices.first["delta"]?
          if content = delta.try(&.["content"]?).try(&.as_s?)
            text << content
            yield content
          end
          if dtcs = delta.try(&.["tool_calls"]?).try(&.as_a?)
            dtcs.each do |dtc|
              index = dtc["index"]?.try(&.as_i?) || 0
              slot = tool_calls[index] ||= {nil, String::Builder.new}
              if name = dtc["function"]?.try(&.["name"]?).try(&.as_s?)
                tool_calls[index] = {name, slot[1]}
              end
              if args = dtc["function"]?.try(&.["arguments"]?).try(&.as_s?)
                tool_calls[index] = {tool_calls[index][0], slot[1] << args}
              end
            end
          end
        end

        calls = tool_calls.keys.sort.map do |i|
          name, args = tool_calls[i]
          ToolCall.new("call_#{i}", name.to_s, args.to_s)
        end
        ProviderResponse.new(calls.empty? ? text.to_s : nil, calls, usage)
      end
    end
  end
end
