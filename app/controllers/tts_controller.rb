class TtsController < ApplicationController
  before_action :set_note

  def status
    authorize @note, :show?

    language = params[:language].presence || @note.detected_language || "en-US"

    registry_status = Tts::ProviderRegistry.status
    voices = {}
    registry_status[:available_providers].each do |provider_name|
      voices[provider_name] = Tts::ProviderRegistry.voices_for(provider_name, language: language)
    end

    active_asset = find_active_asset
    asset_info = active_asset ? serialize_asset(active_asset) : nil

    # Check for audio on a previous revision (stale audio notice)
    stale_audio = nil
    if active_asset.nil?
      prev_revision = find_latest_audio_revision
      if prev_revision && prev_revision.id != @note.head_revision_id
        prev_asset = prev_revision.note_tts_assets.ready.first
        stale_audio = {
          revision_id: prev_revision.id,
          revision_created_at: prev_revision.created_at&.iso8601,
          asset: serialize_asset(prev_asset)
        } if prev_asset
      end
    end

    render json: registry_status.merge(
      voices: voices,
      active_asset: asset_info,
      head_revision_id: @note.head_revision_id,
      stale_audio: stale_audio
    )
  end

  def create
    authorize @note, :update?

    revision = ensure_checkpoint_for_tts(params[:text].to_s)
    result = Tts::GenerateService.call(
      note: @note,
      note_revision: revision,
      text: params[:text].to_s,
      language: params[:language].to_s,
      voice: params[:voice].to_s,
      provider_name: params[:provider].to_s,
      model: params[:model],
      format: params[:audio_format].presence || "mp3",
      settings: params[:settings]&.to_unsafe_h || {}
    )

    render json: {
      tts_asset_id: result[:tts_asset].id,
      ai_request_id: result[:ai_request]&.id,
      cached: result[:cached],
      revision_id: revision.id
    }, status: :accepted
  rescue Tts::Error => e
    render json: {error: e.message}, status: :unprocessable_entity
  end

  def show
    authorize @note, :show?

    asset = find_active_asset
    return render json: {error: "Nenhum audio ativo."}, status: :not_found unless asset

    render json: serialize_asset(asset)
  end

  def reject
    authorize @note, :update?

    asset = NoteTtsAsset.find_by(id: params[:tts_asset_id])
    return render json: {error: "Asset nao encontrado."}, status: :not_found unless asset

    asset.deactivate!
    render json: {status: "rejected", id: asset.id}
  end

  def library
    authorize @note, :show?

    assets = NoteTtsAsset.for_note(@note).order(created_at: :desc).limit(50)
    render json: {assets: assets.map { |a| serialize_asset(a) }}
  end

  def audio
    authorize @note, :show?

    asset = NoteTtsAsset.find_by(id: params[:tts_asset_id])
    if asset&.audio&.attached?
      redirect_to rails_blob_url(asset.audio, disposition: :inline), allow_other_host: true
    else
      render json: {error: "Audio nao disponivel."}, status: :not_found
    end
  end

  private

  def set_note
    @note = Note.active.find_by(slug: params[:slug]) ||
      Note.active.find_by!(id: params[:slug])
  end

  def resolve_revision
    @note.head_revision || @note.note_revisions.order(created_at: :desc).first!
  end

  # If editor content differs from head_revision, create a checkpoint first
  def ensure_checkpoint_for_tts(text)
    head = @note.head_revision
    return resolve_revision if head.nil?

    editor_text = text.to_s.strip
    head_text = head.content_markdown.to_s.strip

    if editor_text == head_text || editor_text.blank?
      head
    else
      # Auto-checkpoint so TTS is always tied to a saved revision
      result = Notes::CheckpointService.call(
        note: @note,
        content: editor_text
      )
      @note.reload
      result.revision
    end
  end

  def find_active_asset
    return nil unless @note.head_revision

    @note.head_revision.note_tts_assets.ready.first ||
      @note.head_revision.note_tts_assets.pending.first
  end

  # Find the most recent revision (any) that has a ready audio asset
  def find_latest_audio_revision
    NoteTtsAsset.for_note(@note)
      .ready
      .order(created_at: :desc)
      .first
      &.note_revision
  end

  def serialize_asset(asset)
    {
      id: asset.id,
      revision_id: asset.note_revision_id,
      language: asset.language,
      voice: asset.voice,
      provider: asset.provider,
      model: asset.model,
      format: asset.format,
      duration_ms: asset.duration_ms,
      ready: asset.ready?,
      pending: asset.pending?,
      audio_url: asset.ready? ? rails_blob_url(asset.audio, disposition: :inline) : nil,
      alignment_status: asset.alignment_status,
      alignment_data: asset.alignment_ready? ? asset.alignment_data : nil,
      created_at: asset.created_at&.iso8601
    }
  end
end
