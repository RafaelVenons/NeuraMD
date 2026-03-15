class NoteRevision < ApplicationRecord
  SEARCH_UUID_RE = /\b(?:[a-z]:)?[0-9a-f]{8}(?:[-\s]?[0-9a-f]{4}){3}[-\s]?[0-9a-f]{12}\b/i

  belongs_to :note
  belongs_to :author, class_name: "User", optional: true
  belongs_to :base_revision, class_name: "NoteRevision", optional: true
  has_many :derived_revisions, class_name: "NoteRevision", foreign_key: :base_revision_id
  has_many :note_links, foreign_key: :created_in_revision_id, dependent: :restrict_with_error
  has_many :note_tts_assets, dependent: :destroy
  has_many :ai_requests, dependent: :destroy
  has_many_attached :assets

  encrypts :content_markdown

  enum :revision_kind, {draft: "draft", checkpoint: "checkpoint"}, prefix: false

  validates :content_markdown, presence: true
  validates :note_id, presence: true
  validates :revision_kind, presence: true

  before_save :derive_content_plain

  def search_preview_text(limit: nil)
    text = content_plain.to_s
      .gsub(SEARCH_UUID_RE, " ")
      .gsub(/\s+/, " ")
      .strip

    limit ? text.truncate(limit) : text
  end

  private

  def derive_content_plain
    return unless content_markdown_changed?
    self.content_plain = content_markdown
      .gsub(/#{Regexp.escape("```")}.*?#{Regexp.escape("```")}/m, " ")
      .gsub(/[#*_`\[\]()!>|-]/, " ")
      .gsub(/https?:\/\/\S+/, " ")
      .gsub(/\s+/, " ")
      .strip
  end
end
