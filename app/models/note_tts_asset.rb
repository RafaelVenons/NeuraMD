class NoteTtsAsset < ApplicationRecord
  PROVIDERS = %w[elevenlabs fish_audio openai].freeze
  FORMATS = %w[mp3 wav opus].freeze

  belongs_to :note_revision
  has_one_attached :audio

  validates :language, presence: true
  validates :voice, presence: true
  validates :provider, presence: true, inclusion: {in: PROVIDERS}
  validates :format, inclusion: {in: FORMATS}
  validates :text_sha256, presence: true
  validates :settings_hash, presence: true

  scope :active, -> { where(is_active: true) }
  scope :inactive, -> { where(is_active: false) }

  def self.find_cached(text_sha256:, language:, voice:, provider:, model:, settings_hash:)
    active.find_by(
      text_sha256: text_sha256,
      language: language,
      voice: voice,
      provider: provider,
      model: model,
      settings_hash: settings_hash
    )
  end

  def deactivate!
    update!(is_active: false)
  end
end
