# Rendering pipeline: ERB-syntax templates compiled at build time into
# methods that append to an output buffer, with Rails semantics —
# `<%= %>` escapes unsafe strings, `<% %>` is control code, block
# helpers (`form_with do ... end`, `content_for do ... end`) work by
# appending to the shared buffer inside the block.
#
# The template compiler is `template_processor.cr`, executed through
# the macro `run()` mechanism (same trick as stdlib ECR).

module ActionView
  module Rendering
    # Compiled template output goes here. Swapped by `capture` so
    # content_for blocks don't leak into the page.
    @__av_buf : IO::Memory = IO::Memory.new
    @__av_content : Hash(String, SafeString) = {} of String => SafeString

    # Raw append (template text, safe HTML).
    def __av_out(value : String) : Nil
      @__av_buf << value
    end

    def __av_out(value : SafeString) : Nil
      @__av_buf << value.raw
    end

    # Escaping append — what `<%= expr %>` compiles to.
    def __av_esc(value : String) : Nil
      @__av_buf << HTML.escape(value)
    end

    def __av_esc(value : SafeString) : Nil
      @__av_buf << value.raw
    end

    def __av_esc(value) : Nil
      @__av_buf << value.to_s
    end

    # Runs the block against a fresh buffer and returns what it wrote.
    def capture(&) : String
      outer = @__av_buf
      @__av_buf = IO::Memory.new
      result = yield
      captured = @__av_buf.to_s
      @__av_buf = outer
      # A block whose body only `<%= %>s` appends directly; a block
      # that returns a value without appending keeps that value.
      captured.empty? && result.is_a?(String | SafeString) ? result.to_s : captured
    end

    # content_for/provide: store a named content block for the layout.
    def content_for(key : String | Symbol, &) : Nil
      store_content(key.to_s, SafeString.new(capture { yield }), force: true)
    end

    def provide(key : String | Symbol, &) : Nil
      store_content(key.to_s, SafeString.new(capture { yield }), force: false)
    end

    def content_for?(key : String | Symbol) : Bool
      @__av_content.has_key?(key.to_s)
    end

    private def store_content(key : String, value : SafeString, force : Bool) : Nil
      @__av_content[key] = value if force || !@__av_content[key]?
    end

    # `yield` / `yield :key` inside layouts.
    def content_for(key : String | Symbol) : ActionView::SafeString
      @__av_content[key.to_s]? || SafeString.new("")
    end

    # Compiles an ERB-syntax template into a method returning
    # SafeString. `path` is resolved from the compile-time working
    # directory (like stdlib ECR).
    macro compile_template(name, path)
      def {{ name.id }} : ActionView::SafeString
        @__av_buf = IO::Memory.new
        {{ run("./template_processor", path, "strip") }}
        ActionView::SafeString.new(@__av_buf.to_s)
      end
    end

    # Same, but the method takes a block: layouts use `<%= yield %>` /
    # `<%= yield :key %>` to inject the action's content.
    macro compile_layout(name, path)
      def {{ name.id }}(&) : ActionView::SafeString
        @__av_buf = IO::Memory.new
        {{ run("./template_processor", path) }}
        ActionView::SafeString.new(@__av_buf.to_s)
      end
    end

    # Compiles the class's partials and generates the runtime render
    # helpers. `partials` maps a partial name (as passed to `render`)
    # to a definition: `path` — the .erb file, `locals` — a
    # compile-time map of local variable name to its type:
    #
    #   compile_partials({
    #     "post" => {path: "app/views/_post.html.erb", locals: {"post" => Post}},
    #   })
    #
    # Locals become real local variables inside the compiled method, so
    # templates reference them bare (`<%= post.title %>`), exactly like
    # Rails partials. Crystal forbids `Object` as a generic argument,
    # so the locals-hash value type is the union of all local types
    # (plus Int32 for the collection counter), deduplicated by name —
    # duplicate args inside Union(...) crash the compiler.
    macro compile_partials(partials)
      # Collect and dedupe (by name) the local types; Int32 is always
      # included — collection rendering passes a 0-based counter.
      {% local_types = [] of Nil %}
      {% for _name, defn in partials %}
        {% for _key, t in defn[:locals] %}
          {% local_types << t %}
        {% end %}
      {% end %}
      {% local_types << Int32 %}
      {% uniq = [] of Nil %}
      {% for t in local_types %}
        {% uniq << t unless uniq.map(&.stringify).includes?(t.stringify) %}
      {% end %}

      # The union goes through an alias: a macro-pasted `Union(...)`
      # used directly as a call-site restriction does not unify with
      # the same union written as a hash's value type when sibling
      # classes collapse to a common ancestor (e.g. two AR models) —
      # generics are invariant over distinct instantiations
      # (Crystal 1.21). Through the alias both sides resolve to one
      # type.
      alias AVPartialLocal = Union({% for t in uniq %}{{ t.resolve }}, {% end %})

      {% for name, defn in partials %}
        def __av_partial_{{ name.id.gsub(/[^a-zA-Z0-9_]/, "_").id }}({% for key, type in defn[:locals] %}{{ key.id }} : {{ type }}, {% end %}) : ActionView::SafeString
          outer = @__av_buf
          @__av_buf = IO::Memory.new
          {{ run("./template_processor", defn[:path]) }}
          result = @__av_buf.to_s
          @__av_buf = outer
          ActionView::SafeString.new(result)
        end
      {% end %}

      # NOTE: the union must be pasted through resolved TypeNodes and
      # the dispatcher must be called with a hash already typed as the
      # union — a macro-pasted union used as a call-site restriction
      # binds to the argument's own value type, breaking member casts
      # (Crystal 1.21; hash literals don't upcast to union values).
      def __av_render_partial(name : String, locals : Hash(String, AVPartialLocal)) : ActionView::SafeString
        case name
        {% for name, defn in partials %}
        when {{ name }} then __av_partial_{{ name.id.gsub(/[^a-zA-Z0-9_]/, "_").id }}({% for key, type in defn[:locals] %}locals[{{ key }}].as({{ type }}), {% end %})
        {% end %}
        else raise ArgumentError.new("Missing partial #{name.inspect}")
        end
      end

      # render partial: "name", locals: {...}
      #
      # NOTE: unlike Ruby, the locals hash uses Crystal literal syntax —
      # `locals: {"post" => post}`, not `locals: {post: post}` (a Ruby
      # hash literal is a NamedTuple in Crystal). Documented deviation.
      def render(partial : String, locals : Hash? = nil) : ActionView::SafeString
        h = {} of String => AVPartialLocal
        locals.try { |l| l.each { |k, v| h[k.to_s] = v } }
        __av_render_partial(partial, h)
      end

      # render partial: "name", collection: [...] [, as_local: "item"]
      # [, spacer_template: "gap"]
      #
      # The local name defaults to the partial's basename (Rails
      # semantics); each item also gets a `<name>_counter` local,
      # 0-based (Rails 7.1+ behavior).
      def render(partial : String, *, collection : Array, as_local : String? = nil,
                 locals : Hash? = nil, spacer_template : String? = nil) : ActionView::SafeString
        key = as_local || File.basename(partial)
        ActionView::SafeString.new(String.build do |buf|
          collection.each_with_index do |item, i|
            if spacer_template && i > 0
              buf << __av_render_partial(spacer_template, {} of String => AVPartialLocal).raw
            end
            l = {} of String => AVPartialLocal
            locals.try { |ls| ls.each { |k, v| l[k.to_s] = v } }
            l[key] = item
            l["#{key}_counter"] = i
            buf << __av_render_partial(partial, l).raw
          end
        end)
      end
    end

    # Renders a compiled template method inside a swapped buffer —
    # used for layouts (`content = view.__av_render_action` then
    # layout's `yield` returns it).
    def __av_render_with_content(name : String | Symbol) : ActionView::SafeString
      @__av_content[name.to_s]? || SafeString.new("")
    end
  end
end
