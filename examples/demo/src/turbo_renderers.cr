# Renderer seam для Turbo: броадкасты рендерят партиалы по полному
# пути ("notes/note" из to_partial_path). Компилируем партиал на
# отдельном view-классе — контроллеры уже компилируют его для себя в
# compile_partials, но их методы недоступны вне реквест-цикла.

class TurboRenderer
  include ActionView::Helpers
  include CRails::Routes::UrlHelpers # note_path в партиале при broadcast-рендере

  compile_partials({
    "notes/note" => {path: "app/views/notes/_note.html.erb", locals: {"note" => Note}},
  })

  def render_turbo_partial(partial : String, locals : Hash(String, Turbo::RenderVal)) : String
    h = {} of String => ERBPartialLocal
    locals.each do |k, v|
      h[k] = v.is_a?(Note) ? v : raise ArgumentError.new("unsupported local #{k}: #{v.class}")
    end
    render(partial, h).to_s
  end
end

Turbo.partial_renderer = ->(partial : String, locals : Hash(String, Turbo::RenderVal)) do
  TurboRenderer.new.render_turbo_partial(partial, locals)
end
