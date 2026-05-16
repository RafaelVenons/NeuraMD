class TentacleSession < ApplicationRecord
  STATUSES = %w[alive exited unknown reaped].freeze
  EXIT_REASONS = %w[graceful signal missing_pid forced crash unknown].freeze

  belongs_to :note, foreign_key: :tentacle_note_id, inverse_of: false

  # Uniqueness is scoped to ALIVE sessions only. Exited records keep their
  # socket as forensic state — they don't compete for the path with the next
  # lifecycle. Mirrors the partial unique index in
  # `index_tentacle_sessions_on_dtach_socket_alive`. See the migration's
  # comment for the Codex P1 from PR #55 that motivated this.
  #
  # `dtach_socket` is allow_nil: PTY-mode sessions carry no socket. They
  # are de-duped instead by the per-note alive partial unique index
  # (`index_tentacle_sessions_on_note_alive`) — the atomic cross-process
  # duplicate-spawn guard. That guard lives in the DB index, not a model
  # validation, so the check stays race-free.
  validates :dtach_socket,
    uniqueness: {case_sensitive: true, conditions: -> { where(status: "alive") }},
    allow_nil: true
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
