class TentacleSession < ApplicationRecord
  STATUSES = %w[alive exited unknown reaped].freeze
  EXIT_REASONS = %w[graceful signal missing_pid forced crash unknown].freeze

  belongs_to :note, foreign_key: :tentacle_note_id, inverse_of: false

  validates :dtach_socket, presence: true, uniqueness: {case_sensitive: true}
  validates :command, presence: true
  validates :started_at, presence: true
  validates :status, inclusion: {in: STATUSES}
  validates :exit_reason, inclusion: {in: EXIT_REASONS}, allow_nil: true

  scope :alive, -> { where(status: "alive") }
  scope :recently_ended, -> { where.not(ended_at: nil).order(ended_at: :desc) }
  scope :for_note, ->(note_id) { where(tentacle_note_id: note_id) }

  def alive?
    status == "alive"
  end

  def ended?
    %w[exited reaped].include?(status)
  end

  # Transition helper — only stamps fields that are actually changing so
  # callers can use this from the zombie reaper without smashing a value
  # the runtime already set.
  def mark_ended!(reason:, exit_code: nil, status: "exited", ended_at: Time.current)
    update!(
      status: status,
      ended_at: ended_at,
      exit_reason: reason,
      exit_code: exit_code
    )
  end

  def mark_unknown!
    update!(status: "unknown", last_seen_at: Time.current)
  end

  def touch_seen!
    update_column(:last_seen_at, Time.current)
  end
end
