class AiController < ApplicationController
  before_action :set_note
  before_action :set_request, only: [:show, :retry, :destroy, :create_translated_note, :resolve_queue]

  def status
    authorize @note, :show?
    render json: Ai::ReviewService.status
  end

  def index
    authorize @note, :show?

    requests = AiRequest.joins(:note_revision)
      .where(note_revisions: {note_id: @note.id})
      .recent_first
      .first(limit_param)

    render json: {
      requests: requests.map { |request| serialize_request(request) }
    }
  end

  def show
    authorize @note, :show?

    render json: serialize_request(@request)
  end

  def reorder
    authorize @note, :update?

    requests = AiRequest.reorder_for_note!(
      note: @note,
      ordered_request_ids: params[:ordered_request_ids]
    )

    render json: {
      requests: requests.map { |request| serialize_request(request.reload) }
    }
  end

  def retry
    authorize @note, :update?

    Ai::ReviewService.retry_request!(@request)

    render json: serialize_request(@request.reload)
  rescue Ai::Error => e
    render json: {error: e.message}, status: :unprocessable_entity
  end

  def resolve_queue
    authorize @note, :update?

    @request.mark_queue_hidden!
    render json: serialize_request(@request.reload)
  end

  def review
    authorize @note, :update?

    text = params[:text].to_s
    document_markdown = params[:document_markdown].to_s

    if text.blank?
      return render json: { error: "Nenhum texto para processar." }, status: :bad_request
    end

    request = Ai::ReviewService.enqueue(
      note: @note,
      note_revision: resolve_note_revision(document_markdown),
      capability: params[:capability],
      text: text,
      language: @note.detected_language,
      target_language: params[:target_language],
      provider_name: params[:provider],
      model_name: params[:model],
      requested_by: current_user
    )

    render json: {
      request_id: request.id,
      status: request.status
    }, status: :accepted
  rescue Ai::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    authorize @note, :update?

    cleanup_result = nil
    request =
      if @request.capability == "seed_note"
        cleanup_result = Notes::PromiseCleanupService.call(ai_request: @request)
        @request.mark_queue_hidden!
        @request.reload
      else
        Ai::ReviewService.cancel_request!(@request)
      end

    render json: {
      id: request.id,
      status: request.status,
      undone: cleanup_result.present?,
      promise_note_id: request.metadata["promise_note_id"],
      promise_note_deleted: cleanup_result&.note_deleted || false,
      restored_content: cleanup_result&.source_content,
      graph_changed: cleanup_result&.graph_changed || false
    }
  end

  def create_translated_note
    authorize @note, :update?
    authorize Note.new, :create?

    translated_note = Notes::TranslationNoteService.call(
      source_note: @note,
      ai_request: @request,
      content: params[:content].to_s,
      target_language: params[:target_language].to_s,
      title: params[:title].to_s,
      author: current_user
    )

    render json: {
      note_id: translated_note.id,
      note_slug: translated_note.slug,
      note_url: note_path(translated_note.slug)
    }, status: :created
  rescue Ai::Error, ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_note
    @note = Note.active.find_by(slug: params[:slug]) ||
      Note.active.find_by!(id: params[:slug])
  end

  def set_request
    @request = AiRequest.joins(:note_revision)
      .where(id: params[:request_id], note_revisions: {note_id: @note.id})
      .first!
  end

  def resolve_note_revision(document_markdown)
    current_content = document_markdown.to_s
    return @note.note_revisions.find_by(revision_kind: :draft) || @note.head_revision if current_content.blank?

    draft = @note.note_revisions.find_by(revision_kind: :draft)
    return draft if draft&.content_markdown == current_content
    return @note.head_revision if @note.head_revision&.content_markdown == current_content

    Notes::DraftService.call(note: @note, content: current_content, author: current_user)
  end

  def serialize_request(request)
    request.realtime_payload
  end

  def limit_param
    value = params[:limit].to_i
    return 10 if value <= 0

    [value, 50].min
  end
end
