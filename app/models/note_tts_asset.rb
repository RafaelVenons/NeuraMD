class NoteTtsAsset < ApplicationRecord
  PROVIDERS = %w[elevenlabs fish_audio gemini kokoro].freeze
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
  scope :ready, -> { active.joins(:audio_attachment) }
  scope :pending, -> { active.left_joins(:audio_attachment).where(active_storage_attachments: {id: nil}) }
  scope :for_note, ->(note) { joins(:note_revision).where(note_revisions: {note_id: note.id}) }

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

  def ready?
    audio.attached?
  end

  def pending?
    is_active && !audio.attached?
  end

  def alignment_ready?
    alignment_status == "succeeded" && alignment_data.present?
  end

  def alignment_pending?
    alignment_status == "pending"
  end

  def alignment_failed?
    alignment_status == "failed"
  end
end
