class NotesController < ApplicationController
  @notes : Array(Note) = [] of Note
  @note : Note? = nil

  def index
    @notes = Note.order(id: :desc).limit(30).to_a
  end

  def show
    note = Note.find(params["id"].to_s.to_i64)
    note.views = (note.views || 0_i64) + 1
    note.save(validate: false)
    @note = note
  end

  def new
    @note = Note.new
  end

  def create
    note = Note.new
    note.title = params["title"].to_s
    note.body = params["body"].to_s
    note.color = params["color"].to_s
    note.views = 0
    if note.save
      redirect_to("/notes/#{note.id}", notice: "Заметка создана")
    else
      @note = note
      render_action("new", 422)
    end
  end

  def destroy
    note = Note.find(params["id"].to_s.to_i64)
    note.destroy
    @note = note
    respond_to do |format|
      # Turbo-браузер получит destroy.turbo_stream.erb (remove карточки);
      # он же уходит всем подписанным страницам через /cable (broadcasts).
      format.turbo_stream
      format.html { redirect_to("/notes", notice: "Заметка удалена") }
    end
  end
end
