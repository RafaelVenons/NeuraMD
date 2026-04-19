class AgentMessage < ApplicationRecord
  belongs_to :from_note, class_name: "Note"
  belongs_to :to_note,   class_name: "Note"

  validates :content, presence: true
  validate  :cannot_send_to_self

  scope :pending,   -> { where(delivered_at: nil).order(:created_at) }
  scope :delivered, -> { where.not(delivered_at: nil) }

  scope :inbox,  ->(note) { where(to_note_id:   note.id).order(created_at: :desc) }
  scope :outbox, ->(note) { where(from_note_id: note.id).order(created_at: :desc) }

  def delivered?
    delivered_at.present?
  end

  def mark_delivered!(now: Time.current)
    return self if delivered?

    update!(delivered_at: now)
    self
  end

  private

  def cannot_send_to_self
    return if from_note_id.blank? || to_note_id.blank?

    errors.add(:to_note_id, "cannot equal from_note_id") if from_note_id == to_note_id
  end
end
