class AiRequest < ApplicationRecord
  CAPABILITIES = %w[suggest rewrite grammar_review tts].freeze

  belongs_to :note_revision

  validates :provider, presence: true
  validates :capability, presence: true, inclusion: {in: CAPABILITIES}
end
