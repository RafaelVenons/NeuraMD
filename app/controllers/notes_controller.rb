class NotesController < ApplicationController
  include ::DomainEvents
  include Notes::SearchActions
  include Notes::RevisionActions
  include Notes::MentionActions

  before_action :set_note, only: [:show, :edit, :update, :destroy, :autosave, :draft, :checkpoint, :revisions, :show_revision, :restore_revision, :link_info, :create_from_promise, :convert_mention, :dismiss_mention]
  layout "editor", only: [:show, :show_revision]

  def index
    authorize Note.new, :index?
    redirect_to graph_path
  end

  def new
    @note = Note.new
    authorize @note
  end

  def create
    @note = Note.new(note_params)
    authorize @note

    if @note.save
      publish_event("note.created", note_id: @note.id, slug: @note.slug, title: @note.title)
      redirect_to note_path(@note.slug, focus: "title"), notice: "Nota criada."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    authorize @note
    if params[:slug] != @note.slug
      if request.format.json?
        @revision = readable_current_revision(@note)
        return render json: ::Notes::ShellPayloadBuilder.call(note: @note, revision: @revision, controller: self)
      end

      redirect_to note_path(@note.slug), status: :moved_permanently and return
    end
    @revision = readable_current_revision(@note)
    respond_to do |format|
      format.html
      format.json { render json: ::Notes::ShellPayloadBuilder.call(note: @note, revision: @revision, controller: self) }
    end
  end

  def edit
    authorize @note
  end

  def update
    authorize @note
    new_title = note_params[:title]
    title_changed = new_title.present? && new_title != @note.title

    if title_changed
      result = Notes::RenameService.call(note: @note, new_title: new_title)
      remaining = note_params.except(:title)
      @note.update!(remaining) if remaining.keys.any?
      redirect_to note_path(result.new_slug), notice: "Nota atualizada."
    elsif @note.update(note_params)
      redirect_to note_path(@note.slug), notice: "Nota atualizada."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @note
    @note.soft_delete!
    redirect_to graph_path, notice: "Nota arquivada."
  end

  def restore
    @note = Note.deleted.find_by!(slug: params[:slug])
    authorize @note, :update?
    @note.restore!
    redirect_to note_path(@note.slug), notice: "Nota restaurada."
  end

  def autosave
    draft
  end

  def draft
    authorize @note, :update?
    result = Notes::DraftService.call(note: @note, content: params[:content_markdown].to_s, author: current_user)
    render json: {saved: true, kind: "draft", graph_changed: result.graph_changed}
  rescue => e
    render json: {error: e.message}, status: :unprocessable_entity
  end

  def checkpoint
    authorize @note, :update?
    result = Notes::CheckpointService.call(
      note: @note,
      content: params[:content_markdown].to_s,
      author: current_user,
      accepted_ai_request: accepted_ai_request_for_checkpoint
    )
    revision = result.revision
    render json: {
      saved: true,
      kind: "checkpoint",
      revision_id: revision.id,
      created_at: revision.created_at.iso8601,
      graph_changed: result.graph_changed
    }
  rescue => e
    render json: {error: e.message}, status: :unprocessable_entity
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

  def create_from_promise
    authorize @note, :update?
    authorize Note.new, :create?

    promise_result = Notes::PromiseCreationService.call(
      source_note: @note,
      title: params[:title],
      author: current_user,
      mode: params[:mode]
    )
    promise_note = promise_result.note

    render json: {
      note_id: promise_note.id,
      note_slug: promise_note.slug,
      note_title: promise_note.title,
      note_url: note_path(promise_note.slug),
      created: promise_result.created,
      seeded: promise_result.seeded,
      request_id: promise_result.request&.id,
      request_status: promise_result.request&.status
    }, status: :created
  rescue Ai::Error, ArgumentError => e
    render json: {error: e.message}, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error("[NotesController#create_from_promise] #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace.present?
    render json: {error: "Falha interna ao criar nota com IA."}, status: :internal_server_error
  end

  private

  def accepted_ai_request_for_checkpoint
    return nil if params[:ai_request_id].blank?

    AiRequest.joins(note_revision: :note)
      .where(id: params[:ai_request_id], notes: {id: @note.id})
      .first!
  end

  def set_note
    @note = Note.active.find_by(slug: params[:slug]) ||
      Note.active.find_by(id: params[:slug])

    return if @note

    redirect_record = SlugRedirect.includes(:note).find_by(slug: params[:slug])
    if redirect_record&.note && !redirect_record.note.deleted?
      redirect_to note_path(redirect_record.note.slug), status: :moved_permanently
      return
    end

    alias_record = NoteAlias.includes(:note).where("lower(name) = lower(?)", params[:slug]).first
    if alias_record&.note && !alias_record.note.deleted?
      redirect_to note_path(alias_record.note.slug), status: :moved_permanently
      return
    end

    raise ActiveRecord::RecordNotFound
  end

  def note_params
    params.require(:note).permit(:title, :note_kind, :detected_language)
  end

  def readable_current_revision(note)
    candidates = []
    draft = note.note_revisions.find_by(revision_kind: :draft)
    if draft.present? && draft_fresh?(draft, note)
      candidates << draft
    end
    candidates << note.head_revision if note.head_revision.present?

    remaining_checkpoints = note.note_revisions
      .where(revision_kind: :checkpoint)
      .where.not(id: candidates.compact.map(&:id))
      .order(created_at: :desc)

    remaining_checkpoints.find_each do |revision|
      candidates << revision
    end

    candidates.compact.find do |revision|
      readable_revision?(revision)
    end
  end

  def readable_revision?(revision)
    revision.content_markdown
    true
  rescue ActiveRecord::Encryption::Errors::Decryption => e
    Rails.logger.warn("[NotesController] unreadable revision #{revision.id} for note #{revision.note_id}: #{e.class}")
    false
  end

  def draft_fresh?(draft, note)
    return true if note.head_revision_id.blank?
    draft.base_revision_id == note.head_revision_id
  end
end
