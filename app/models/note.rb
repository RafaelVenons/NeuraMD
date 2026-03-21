class Note < ApplicationRecord
  NOTE_KINDS = %w[markdown mixed].freeze
  SUPPORTED_LANGUAGES = %w[pt-BR en-US zh-CN zh-TW ja-JP ko-KR es de fr it].freeze

  belongs_to :head_revision, class_name: "NoteRevision", optional: true
  has_many :note_revisions, dependent: :destroy
  has_many :outgoing_links, class_name: "NoteLink", foreign_key: :src_note_id, dependent: :destroy
  has_many :incoming_links, class_name: "NoteLink", foreign_key: :dst_note_id, dependent: :destroy
  has_many :active_outgoing_links, -> { active }, class_name: "NoteLink", foreign_key: :src_note_id
  has_many :active_incoming_links, -> { active }, class_name: "NoteLink", foreign_key: :dst_note_id
  has_many :note_tags, dependent: :destroy
  has_many :tags, through: :note_tags

  validates :title, presence: true
  validates :slug, presence: true, uniqueness: {case_sensitive: false}
  validates :note_kind, inclusion: {in: NOTE_KINDS}

  before_validation :generate_slug, on: :create

  scope :active, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }
  scope :search_by_title, ->(query, exclude_id: nil) {
    normalized = query.to_s.strip
    relation = active
    relation = relation.where.not(id: exclude_id) if exclude_id.present?
    next relation.order(:title).limit(10) if normalized.blank?

    pattern = "%#{sanitize_sql_like(normalized)}%"
    sanitized_query = connection.quote_string(normalized)
    similarity_sql = "similarity(title, '#{sanitized_query}')"

    relation
      .where("title ILIKE :pattern OR #{similarity_sql} > 0.12", pattern:)
      .select("notes.*, #{similarity_sql} AS title_similarity")
      .order(Arel.sql("CASE WHEN title ILIKE #{connection.quote(pattern)} THEN 0 ELSE 1 END ASC, title_similarity DESC, title ASC"))
      .limit(10)
  }

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def restore!
    update!(deleted_at: nil)
  end

  def deleted?
    deleted_at.present?
  end

  private

  def generate_slug
    return if slug.present?
    base = title.to_s.downcase.gsub(/[^\w\s-]/, "").gsub(/\s+/, "-").gsub(/-+/, "-").strip
    self.slug = unique_slug(base)
  end

  def unique_slug(base)
    candidate = base.presence || "nota"
    counter = 0
    loop do
      slug = counter.zero? ? candidate : "#{candidate}-#{counter}"
      return slug unless Note.exists?(slug: slug)
      counter += 1
    end
  end
end
