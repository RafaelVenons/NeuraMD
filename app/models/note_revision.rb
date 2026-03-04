class NoteRevision < ApplicationRecord
  belongs_to :note
  belongs_to :author, class_name: "User", optional: true
  belongs_to :base_revision, class_name: "NoteRevision", optional: true
  has_many :derived_revisions, class_name: "NoteRevision", foreign_key: :base_revision_id
  has_many :note_links, foreign_key: :created_in_revision_id, dependent: :restrict_with_error
  has_many :note_tts_assets, dependent: :destroy
  has_many :ai_requests, dependent: :destroy
  has_many_attached :assets

  encrypts :content_markdown

  validates :content_markdown, presence: true
  validates :note_id, presence: true

  before_save :derive_content_plain

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
