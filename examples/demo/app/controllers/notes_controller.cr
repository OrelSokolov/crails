class NotesController < ApplicationController
  @notes : Array(Note) = [] of Note
  @note : Note? = nil

  before_action :set_note, only: [:show, :destroy]

  # GET /notes
  def index
    @notes = Note.order(id: :desc).limit(30).to_a
  end

  # GET /notes/:id — +1 просмотр за показ
  def show
    note = @note.not_nil!
    note.views = (note.views || 0_i64) + 1
    note.save(validate: false)
  end

  # GET /notes/new
  def new
    @note = Note.new
  end

  # POST /notes
  def create
    note = Note.new
    note.title = note_params["title"].to_s
    note.body = note_params["body"].to_s
    note.color = note_params["color"].to_s
    if note.save
      redirect_to(note_path(note), notice: "Note was successfully created.")
    else
      @note = note
      render_action("new", 422)
    end
  end

  # DELETE /notes/:id
  def destroy
    @note.not_nil!.destroy
    respond_to do |format|
      # Turbo-браузер получит destroy.turbo_stream.erb (remove карточки);
      # он же уходит всем подписанным страницам через /cable (broadcasts).
      format.turbo_stream
      format.html { redirect_to(notes_path, notice: "Note was successfully deleted.") }
    end
  end

  private def set_note : Nil
    @note = Note.find(params["id"].to_s.to_i64)
  end

  private def note_params
    params.require(:note).permit(:title, :body, :color)
  end
end
