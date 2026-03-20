class AiController < ApplicationController
  before_action :set_note
  before_action :set_request, only: [:show, :destroy]

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

    request = Ai::ReviewService.cancel_request!(@request)

    render json: {
      id: request.id,
      status: request.status
    }
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
