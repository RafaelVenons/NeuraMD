class AiController < ApplicationController
  before_action :set_note

  def status
    authorize @note, :show?
    render json: Ai::ReviewService.status
  end

  def review
    authorize @note, :update?

    text = params[:text].to_s
    document_markdown = params[:document_markdown].to_s

    if text.blank?
      return render json: { error: "Nenhum texto para processar." }, status: :bad_request
    end

    result = Ai::ReviewService.call(
      note: @note,
      note_revision: resolve_note_revision(document_markdown),
      capability: params[:capability],
      text: text,
      language: @note.detected_language,
      provider_name: params[:provider]
    )

    render json: {
      original: text,
      corrected: result.content,
      provider: result.provider,
      model: result.model
    }
  rescue Ai::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_note
    @note = Note.active.find_by(slug: params[:slug]) ||
      Note.active.find_by!(id: params[:slug])
  end

  def resolve_note_revision(document_markdown)
    current_content = document_markdown.to_s
    return @note.note_revisions.find_by(revision_kind: :draft) || @note.head_revision if current_content.blank?

    draft = @note.note_revisions.find_by(revision_kind: :draft)
    return draft if draft&.content_markdown == current_content
    return @note.head_revision if @note.head_revision&.content_markdown == current_content

    Notes::DraftService.call(note: @note, content: current_content, author: current_user)
  end
end
