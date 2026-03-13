class NotesController < ApplicationController
  before_action :set_note, only: [:show, :edit, :update, :destroy, :autosave, :draft, :checkpoint, :revisions, :show_revision, :restore_revision, :link_info]
  layout "editor", only: [:show, :show_revision]

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
    # UUID-based URLs (from client-side wiki-link preview) → redirect to slug URL
    if params[:slug] != @note.slug
      redirect_to note_path(@note.slug), status: :moved_permanently and return
    end
    # Load draft for crash recovery if one exists; otherwise use head checkpoint
    @revision = @note.note_revisions.find_by(revision_kind: :draft) || @note.head_revision
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

  def search
    authorize Note.new, :index?
    notes = Note.search_by_title(params[:q].to_s)
    render json: notes.map { |n| {id: n.id, title: n.title, slug: n.slug} }
  end

  def autosave
    # Legacy endpoint — now delegates to draft behaviour
    draft
  end

  def draft
    authorize @note, :update?
    Notes::DraftService.call(note: @note, content: params[:content_markdown].to_s, author: current_user)
    render json: {saved: true, kind: "draft"}
  rescue => e
    render json: {error: e.message}, status: :unprocessable_entity
  end

  def checkpoint
    authorize @note, :update?
    revision = Notes::CheckpointService.call(
      note: @note,
      content: params[:content_markdown].to_s,
      author: current_user,
      change_summary: params[:change_summary]
    )
    render json: {saved: true, kind: "checkpoint", revision_id: revision.id, created_at: revision.created_at.iso8601}
  rescue => e
    render json: {error: e.message}, status: :unprocessable_entity
  end

  def revisions
    authorize @note, :show?
    @revisions = @note.note_revisions.where(revision_kind: :checkpoint).order(created_at: :desc)
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

  def show_revision
    authorize @note, :show?
    @revision = @note.note_revisions.where(revision_kind: :checkpoint).find(params[:revision_id])
  end

  def link_info
    authorize @note, :show?
    link = @note.outgoing_links.includes(:tags).find_by(dst_note_id: params[:dst_uuid])
    if link
      render json: {
        link_id: link.id,
        tags: link.tags.map { |t| {id: t.id, name: t.name, color_hex: t.color_hex || "#3b82f6"} }
      }
    else
      render json: {link_id: nil, tags: []}
    end
  end

  def restore_revision
    authorize @note, :update?
    source = @note.note_revisions.where(revision_kind: :checkpoint).find(params[:revision_id])
    revision = Notes::CheckpointService.call(
      note: @note,
      content: source.content_markdown,
      author: current_user,
      change_summary: "Restaurado de #{source.created_at.strftime("%d/%m/%Y %H:%M")}"
    )
    render json: {saved: true, revision_id: revision.id}
  rescue => e
    render json: {error: e.message}, status: :unprocessable_entity
  end

  private

  def set_note
    @note = Note.active.find_by(slug: params[:slug]) ||
      Note.active.find_by!(id: params[:slug])
  end

  def note_params
    params.require(:note).permit(:title, :slug, :note_kind, :detected_language)
  end
end
