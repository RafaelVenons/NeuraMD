class AiProvider < ApplicationRecord
  NAMES = %w[openai anthropic azure_openai ollama local].freeze

  validates :name, presence: true, uniqueness: true, inclusion: {in: NAMES}

  scope :enabled, -> { where(enabled: true) }
end
