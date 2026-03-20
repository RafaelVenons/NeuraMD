class AiRequest < ApplicationRecord
  CAPABILITIES = %w[suggest rewrite grammar_review tts].freeze
  STATUSES = %w[queued running retrying succeeded failed canceled].freeze
  ERROR_KINDS = %w[transient permanent validation].freeze

  belongs_to :note_revision

  after_commit :broadcast_dashboard_refresh_later
  after_commit :broadcast_note_update_later

  validates :attempts_count, numericality: {greater_than_or_equal_to: 0}
  validates :max_attempts, numericality: {greater_than: 0}
  validates :last_error_kind, inclusion: {in: ERROR_KINDS}, allow_nil: true
  validates :status, presence: true, inclusion: {in: STATUSES}
  validates :provider, presence: true
  validates :capability, presence: true, inclusion: {in: CAPABILITIES}

  scope :recent_first, -> { order(created_at: :desc) }
  scope :active, -> { where(status: %w[queued running retrying]) }

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
    return false unless provider == "ollama"

    if running? && started_at.present?
      return started_at < now - remote_long_job_after
    end

    if (queued? || retrying?) && created_at.present?
      return created_at < now - remote_long_job_after
    end

    false
  end

  def remote_status_hint(now: Time.current)
    return nil unless provider == "ollama"

    return "Job remoto aguardando a vez na fila local. Pode fechar e voltar depois." if queued?
    return "Nova tentativa agendada para reenviar ao AIrch." if retrying?
    return "Job remoto longo no AIrch. Pode fechar e voltar depois." if remote_long_job?(now:)
    return "Processando no AIrch. Em CPU-only isso pode levar varios minutos." if running?

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
    {
      id: id,
      status: status,
      provider: provider,
      model: model,
      capability: capability,
      attempts_count: attempts_count,
      max_attempts: max_attempts,
      next_retry_at: next_retry_at&.iso8601,
      last_error_kind: last_error_kind,
      corrected: output_text,
      error: error_message,
      created_at: created_at.iso8601,
      started_at: started_at&.iso8601,
      completed_at: completed_at&.iso8601,
      duration_ms: duration_ms,
      duration_human: duration_human,
      remote_long_job: remote_long_job?,
      remote_hint: remote_status_hint
    }
  end

  private

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
    provider_default = provider == "ollama" ? ollama_default : default
    env_key = provider == "ollama" ? "OLLAMA_#{suffix}" : "AI_REQUEST_#{suffix}"
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
end
