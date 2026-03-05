class NotesController < ApplicationController
  before_action :set_note, only: [:show, :edit, :update, :destroy, :autosave, :revisions]
  layout "editor", only: [:show]

  def index
    @notes = policy_scope(Note).order(updated_at: :desc)
  end

  def new
    @note = Note.new
    authorize @note
  end

  def create
    @note = Note.new(note_params)
    authorize @note

    if @note.save
      redirect_to note_path(@note.slug), notice: "Nota criada."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    authorize @note
    @revision = @note.head_revision
  end

  def edit
    authorize @note
  end

  def update
    authorize @note
    if @note.update(note_params)
      redirect_to note_path(@note.slug), notice: "Nota atualizada."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @note
    @note.soft_delete!
    redirect_to notes_path, notice: "Nota arquivada."
  end

  def autosave
    authorize @note, :update?
    content = params[:content_markdown].to_s
    result = Notes::CreateRevisionService.call(
      note: @note,
      content_markdown: content,
      author: current_user,
      change_summary: params[:change_summary]
    )

    render json: {
      revision_id: result[:revision]&.id,
      created: result[:created],
      message: result[:created] ? "Revisão criada" : "Sem alterações significativas"
    }
  rescue => e
    render json: {error: e.message}, status: :unprocessable_entity
  end

  def revisions
    authorize @note, :show?
    @revisions = @note.note_revisions.order(created_at: :desc).limit(50)
    render json: @revisions.map { |r|
      {
        id: r.id,
        change_summary: r.change_summary,
        ai_generated: r.ai_generated,
        created_at: r.created_at.iso8601,
        is_head: r.id == @note.head_revision_id
      }
    }
  end

  private

  def set_note
    @note = Note.active.find_by!(slug: params[:slug])
  end

  def note_params
    params.require(:note).permit(:title, :slug, :note_kind, :detected_language)
  end
end
