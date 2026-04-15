class AiRequest < ApplicationRecord
  CAPABILITIES = %w[rewrite grammar_review translate tts seed_note].freeze
  STATUSES = %w[queued running retrying succeeded failed canceled].freeze
  ERROR_KINDS = %w[transient permanent validation].freeze

  belongs_to :note_revision

  before_validation :assign_queue_position, on: :create

  after_commit :broadcast_dashboard_refresh_later
  after_commit :broadcast_note_update_later
  after_commit :broadcast_queue_update_later

  validates :attempts_count, numericality: {greater_than_or_equal_to: 0}
  validates :max_attempts, numericality: {greater_than: 0}
  validates :queue_position, numericality: {greater_than: 0}
  validates :last_error_kind, inclusion: {in: ERROR_KINDS}, allow_nil: true
  validates :status, presence: true, inclusion: {in: STATUSES}
  validates :provider, presence: true
  validates :capability, presence: true, inclusion: {in: CAPABILITIES}

  scope :recent_first, -> { order(created_at: :desc) }
  scope :active, -> { where(status: %w[queued running retrying]) }
  scope :reorderable, -> { where(status: %w[queued running retrying]) }
  scope :queue_order, -> { order(:queue_position, :created_at, :id) }

  def queued?
    status == "queued"
  end

  def running?
    status == "running"
  end

  def succeeded?
    status == "succeeded"
  end

  def failed?
    status == "failed"
  end

  def retrying?
    status == "retrying"
  end

  def canceled?
    status == "canceled"
  end

  def retryable?
    attempts_count < max_attempts
  end

  def active?
    queued? || running? || retrying?
  end

  def reorderable?
    queued? || running? || retrying?
  end

  def duration_ms
    return nil if started_at.blank?

    finished_at = completed_at || Time.current
    ((finished_at - started_at) * 1000).round
  end

  def duration_human(now: Time.current)
    reference_time =
      if started_at.present?
        started_at
      elsif queued? || retrying?
        created_at
      end

    return "—" if reference_time.blank?

    seconds = [(completed_at || now) - reference_time, 0].max.to_i
    return "#{seconds}s" if seconds < 60

    minutes = seconds / 60
    remainder_seconds = seconds % 60
    return "#{minutes}min" if minutes >= 60 || remainder_seconds.zero?

    "#{minutes}min #{remainder_seconds}s"
  end

  def remote_long_job?(now: Time.current)
    return false unless provider.start_with?("ollama")

    if running? && started_at.present?
      return started_at < now - remote_long_job_after
    end

    if (queued? || retrying?) && created_at.present?
      return created_at < now - remote_long_job_after
    end

    false
  end

  def remote_status_hint(now: Time.current)
    return nil unless provider.start_with?("ollama")

    host = provider == "ollama" ? "Bazzite" : provider.delete_prefix("ollama_").capitalize
    return "Job remoto aguardando a vez na fila local. Pode fechar e voltar depois." if queued?
    return "Nova tentativa agendada para reenviar ao #{host}." if retrying?
    return "Job remoto longo no #{host}. Pode fechar e voltar depois." if remote_long_job?(now:)
    return "Processando no #{host}. Em CPU-only isso pode levar varios minutos." if running?

    nil
  end

  def stuck?(now: Time.current)
    return true if retrying? && next_retry_at.present? && next_retry_at < now - retry_grace_period
    return true if running? && started_at.present? && started_at < now - running_stuck_after
    return true if queued? && created_at.present? && created_at < now - queued_stuck_after

    false
  end

  def stuck_reason(now: Time.current)
    return "Retry atrasado" if retrying? && next_retry_at.present? && next_retry_at < now - retry_grace_period
    return "Execução longa" if running? && started_at.present? && started_at < now - running_stuck_after
    return "Fila antiga" if queued? && created_at.present? && created_at < now - queued_stuck_after

    nil
  end

  def realtime_payload
    promise_note = promise_note_record
    translated_note = translated_note_record

    payload = {
      id: id,
      status: status,
      provider: provider,
      model: model,
      capability: capability,
      note_id: note_revision&.note_id,
      note_slug: note_revision&.note&.slug,
      note_title: note_revision&.note&.title,
      queue_position: queue_position,
      source_language: metadata_payload["language"],
      target_language: metadata_payload["target_language"],
      attempts_count: attempts_count,
      max_attempts: max_attempts,
      next_retry_at: next_retry_at&.iso8601,
      last_error_kind: last_error_kind,
      input_text: input_text,
      corrected: output_text,
      error: error_message,
      created_at: created_at.iso8601,
      started_at: started_at&.iso8601,
      completed_at: completed_at&.iso8601,
      duration_ms: duration_ms,
      duration_human: duration_human,
      remote_long_job: remote_long_job?,
      remote_hint: remote_status_hint,
      accepted_at: metadata_payload["accepted_at"],
      translation_applied_at: metadata_payload["translation_applied_at"],
      queue_hidden_at: metadata_payload["queue_hidden_at"],
      promise_source_note_id: metadata_payload["promise_source_note_id"],
      promise_source_note_slug: metadata_payload["promise_source_note_slug"],
      promise_note_id: metadata_payload["promise_note_id"],
      promise_note_title: metadata_payload["promise_note_title"],
      promise_note_slug: promise_note&.slug,
      translated_note_id: metadata_payload["translated_note_id"],
      translated_note_title: translated_note&.title,
      translated_note_slug: translated_note&.slug,
      result_applicable: result_applicable?,
      queue_hidden: queue_hidden?
    }

    if capability == "tts"
      tts_asset = NoteTtsAsset.find_by(id: metadata_payload["tts_asset_id"])
      payload.merge!(
        tts_asset_id: metadata_payload["tts_asset_id"],
        tts_voice: metadata_payload["voice"],
        tts_language: metadata_payload["language"],
        tts_format: metadata_payload["format"],
        tts_audio_ready: tts_asset&.ready? || false,
        tts_duration_ms: tts_asset&.duration_ms
      )
    end

    payload
  end

  def queue_hidden?
    metadata_payload["queue_hidden_at"].present?
  end

  def mark_queue_hidden!
    update!(metadata: metadata_payload.merge("queue_hidden_at" => Time.current.iso8601))
  end

  def clear_queue_hidden!
    return unless queue_hidden?

    next_metadata = metadata_payload.except("queue_hidden_at")
    update!(metadata: next_metadata)
  end

  def result_applicable?
    return false unless succeeded?

    case capability
    when "seed_note"
      promise_note_record.present? && !queue_hidden?
    when "translate"
      output_text.present? && metadata_payload["translation_applied_at"].blank? && translated_note_record.blank?
    else
      output_text.present? && metadata_payload["accepted_at"].blank?
    end
  end

  private

  def metadata_payload
    self[:metadata] || {}
  end

  def assign_queue_position
    self.queue_position ||= self.class.next_queue_position
  end

  def promise_note_record
    promise_note_id = metadata_payload["promise_note_id"]
    return nil if promise_note_id.blank?

    Note.active.find_by(id: promise_note_id)
  end

  def translated_note_record
    translated_note_id = metadata_payload["translated_note_id"]
    return nil if translated_note_id.blank?

    Note.active.find_by(id: translated_note_id)
  end

  class << self
    def next_queue_position
      maximum(:queue_position).to_i + 1
    end

    def reorder_for_note!(note:, ordered_request_ids:)
      request_ids = Array(ordered_request_ids).map(&:to_s)

      transaction do
        scoped = joins(:note_revision)
          .where(note_revisions: {note_id: note.id})
          .reorderable
          .queue_order
          .to_a

        by_id = scoped.index_by { |request| request.id.to_s }
        ordered = request_ids.filter_map { |id| by_id[id] }
        remaining = scoped.reject { |request| request_ids.include?(request.id.to_s) }
        final = ordered + remaining

        final.each_with_index do |request, index|
          next_position = index + 1
          next if request.queue_position == next_position

          request.update!(queue_position: next_position)
        end

        final
      end
    end

    def reorder_globally!(ordered_request_ids:)
      request_ids = Array(ordered_request_ids).map(&:to_s)

      transaction do
        scoped = reorderable.queue_order.to_a
        by_id = scoped.index_by { |request| request.id.to_s }
        ordered = request_ids.filter_map { |id| by_id[id] }
        remaining = scoped.reject { |request| request_ids.include?(request.id.to_s) }
        final = ordered + remaining

        final.each_with_index do |request, index|
          next_position = index + 1
          next if request.queue_position == next_position

          request.update!(queue_position: next_position)
        end

        final
      end
    end

    def next_ready_request(now: Time.current)
      where(status: "queued")
        .or(where(status: "retrying").where("next_retry_at IS NULL OR next_retry_at <= ?", now))
        .queue_order
        .first
    end
  end

  def remote_long_job_after
    timeout_window_for("LONG_JOB_AFTER", default: 45.seconds, ollama_default: 45.seconds)
  end

  def running_stuck_after
    timeout_window_for("RUNNING_STUCK_AFTER", default: 5.minutes, ollama_default: 3.hours)
  end

  def queued_stuck_after
    timeout_window_for("QUEUED_STUCK_AFTER", default: 5.minutes, ollama_default: 6.hours)
  end

  def retry_grace_period
    timeout_window_for("RETRY_GRACE_PERIOD", default: 1.minute, ollama_default: 10.minutes)
  end

  def timeout_window_for(suffix, default:, ollama_default:)
    is_ollama = provider.start_with?("ollama")
    provider_default = is_ollama ? ollama_default : default
    env_key = is_ollama ? "#{provider.upcase.tr("-", "_")}_#{suffix}" : "AI_REQUEST_#{suffix}"
    seconds = ENV[env_key].to_i
    seconds.positive? ? seconds.seconds : provider_default
  end

  def broadcast_dashboard_refresh_later
    broadcast_refresh_later_to "ai_requests_dashboard"
  end

  def broadcast_note_update_later
    return unless note_revision&.note.present?

    Turbo::StreamsChannel.broadcast_action_later_to(
      note_revision.note,
      :ai_requests,
      action: :dispatch_event,
      target: "editor-root",
      attributes: {
        name: "ai-request:update",
        detail: realtime_payload.to_json
      },
      render: false
    )
  end

  def broadcast_queue_update_later
    Turbo::StreamsChannel.broadcast_action_later_to(
      "ai_requests_queue",
      action: :dispatch_event,
      target: "editor-root",
      attributes: {
        name: "ai-request:update",
        detail: realtime_payload.to_json
      },
      render: false
    )
  end
end
