# Callbacks: before_validation / before_save / before_destroy /
# after_create / after_update / after_save / after_destroy.
#
# Each declaration generates a hidden prefixed method; the `macro finished`
# in base.cr assembles them into `__run_<hook>` runners. A before-hook
# aborts the chain by returning false (the Rails `throw(:abort)`
# equivalent — symbols cannot be thrown in Crystal).

module ActiveRecord
  class Base
    # Runner defaults (overridden per model by the finished codegen).
    def __run_before_validation : Bool
      true
    end

    def __run_before_save : Bool
      true
    end

    def __run_before_destroy : Nil
    end

    def __run_after_create : Nil
    end

    def __run_after_update : Nil
    end

    def __run_after_save : Nil
    end

    def __run_after_destroy : Nil
    end

    def __run_dependents : Nil
    end

    def __run_after_commit(event : Symbol) : Nil
    end

    def __run_after_rollback(event : Symbol) : Nil
    end

    # --- DSL (flat definitions: a macro cannot be emitted by a macro) ---

    macro before_validation(method_name = nil, &block)
      {% n = @type.methods.select { |m| m.name.stringify.starts_with?("before_validation__cb_") }.size %}
      {% if method_name %}
        def before_validation__cb_{{n.id}} : Bool
          {{method_name.id}}
          true
        end
      {% else %}
        def before_validation__cb_{{n.id}} : Bool
          ({{block.body}}) == false ? false : true
        end
      {% end %}
    end

    macro before_save(method_name = nil, &block)
      {% n = @type.methods.select { |m| m.name.stringify.starts_with?("before_save__cb_") }.size %}
      {% if method_name %}
        def before_save__cb_{{n.id}} : Bool
          {{method_name.id}}
          true
        end
      {% else %}
        def before_save__cb_{{n.id}} : Bool
          ({{block.body}}) == false ? false : true
        end
      {% end %}
    end

    macro before_destroy(method_name = nil, &block)
      {% n = @type.methods.select { |m| m.name.stringify.starts_with?("before_destroy__cb_") }.size %}
      {% if method_name %}
        def before_destroy__cb_{{n.id}} : Nil
          {{method_name.id}}
          nil
        end
      {% else %}
        def before_destroy__cb_{{n.id}} : Nil
          {{block.body}}
          nil
        end
      {% end %}
    end

    macro after_create(method_name = nil, &block)
      {% n = @type.methods.select { |m| m.name.stringify.starts_with?("after_create__cb_") }.size %}
      {% if method_name %}
        def after_create__cb_{{n.id}} : Nil
          {{method_name.id}}
          nil
        end
      {% else %}
        def after_create__cb_{{n.id}} : Nil
          {{block.body}}
          nil
        end
      {% end %}
    end

    macro after_update(method_name = nil, &block)
      {% n = @type.methods.select { |m| m.name.stringify.starts_with?("after_update__cb_") }.size %}
      {% if method_name %}
        def after_update__cb_{{n.id}} : Nil
          {{method_name.id}}
          nil
        end
      {% else %}
        def after_update__cb_{{n.id}} : Nil
          {{block.body}}
          nil
        end
      {% end %}
    end

    macro after_save(method_name = nil, &block)
      {% n = @type.methods.select { |m| m.name.stringify.starts_with?("after_save__cb_") }.size %}
      {% if method_name %}
        def after_save__cb_{{n.id}} : Nil
          {{method_name.id}}
          nil
        end
      {% else %}
        def after_save__cb_{{n.id}} : Nil
          {{block.body}}
          nil
        end
      {% end %}
    end

    macro after_destroy(method_name = nil, &block)
      {% n = @type.methods.select { |m| m.name.stringify.starts_with?("after_destroy__cb_") }.size %}
      {% if method_name %}
        def after_destroy__cb_{{n.id}} : Nil
          {{method_name.id}}
          nil
        end
      {% else %}
        def after_destroy__cb_{{n.id}} : Nil
          {{block.body}}
          nil
        end
      {% end %}
    end

    # dependent: :destroy hooks for associations (associations.cr).
    macro __dependent_destroy(call)
      {% n = @type.methods.select { |m| m.name.stringify.starts_with?("dependent__cb_") }.size %}
      def dependent__cb_{{n.id}} : Nil
        {{ call }}
        nil
      end
    end

    # --- transaction callbacks (transactions.cr) -------------------------
    # Fires on the real COMMIT / any ROLLBACK (incl. savepoints). Without
    # an open transaction it fires per-op (implicit auto-commit tx).
    # `on:` filters by event: :create / :update / :destroy (Symbol or Array).

    macro after_commit(on = nil, method_name = nil, &block)
      {% n = @type.methods.select { |m| m.name.stringify.starts_with?("after_commit__cb_") }.size %}
      {% if method_name %}
        def after_commit__cb_{{n.id}}(event : Symbol) : Nil
          {% if on %}return unless __tx_event_match?(event, {{on}}){% end %}
          {{method_name.id}}
          nil
        end
      {% else %}
        def after_commit__cb_{{n.id}}(event : Symbol) : Nil
          {% if on %}return unless __tx_event_match?(event, {{on}}){% end %}
          {{block.body}}
          nil
        end
      {% end %}
    end

    macro after_rollback(on = nil, method_name = nil, &block)
      {% n = @type.methods.select { |m| m.name.stringify.starts_with?("after_rollback__cb_") }.size %}
      {% if method_name %}
        def after_rollback__cb_{{n.id}}(event : Symbol) : Nil
          {% if on %}return unless __tx_event_match?(event, {{on}}){% end %}
          {{method_name.id}}
          nil
        end
      {% else %}
        def after_rollback__cb_{{n.id}}(event : Symbol) : Nil
          {% if on %}return unless __tx_event_match?(event, {{on}}){% end %}
          {{block.body}}
          nil
        end
      {% end %}
    end
  end
end
