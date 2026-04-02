class Note < ApplicationRecord
  include ::DomainEvents

  NOTE_KINDS = %w[markdown mixed].freeze
  SUPPORTED_LANGUAGES = %w[pt-BR en-US zh-CN zh-TW ja-JP ko-KR es de fr it].freeze

  belongs_to :head_revision, class_name: "NoteRevision", optional: true
  has_many :note_revisions, dependent: :destroy
  has_many :outgoing_links, class_name: "NoteLink", foreign_key: :src_note_id, dependent: :destroy
  has_many :incoming_links, class_name: "NoteLink", foreign_key: :dst_note_id, dependent: :destroy
  has_many :active_outgoing_links, -> { active }, class_name: "NoteLink", foreign_key: :src_note_id
  has_many :active_incoming_links, -> { active }, class_name: "NoteLink", foreign_key: :dst_note_id
  has_many :slug_redirects, dependent: :destroy
  has_many :note_aliases, dependent: :destroy
  has_many :mention_exclusions, dependent: :destroy
  has_many :note_headings, dependent: :destroy
  has_many :note_blocks, dependent: :destroy
  has_many :note_tags, dependent: :destroy
  has_many :tags, through: :note_tags

  validates :title, presence: true
  validates :slug, presence: true, uniqueness: {case_sensitive: false}
  validates :note_kind, inclusion: {in: NOTE_KINDS}

  before_validation :generate_slug, on: :create
  validate :slug_immutable, on: :update

  scope :active, -> { where(deleted_at: nil) }
  scope :with_latest_content, -> { active.where.not(head_revision_id: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }
  scope :search_by_title, ->(query, exclude_id: nil) {
    normalized = query.to_s.strip
    relation = with_latest_content.left_joins(:note_aliases).group("notes.id")
    relation = relation.where.not(id: exclude_id) if exclude_id.present?
    next relation.order(:title).limit(10) if normalized.blank?

    pattern = "%#{sanitize_sql_like(normalized)}%"
    sanitized_query = connection.quote_string(normalized)
    title_sim = "similarity(notes.title, '#{sanitized_query}')"
    alias_sim = "MAX(similarity(note_aliases.name, '#{sanitized_query}'))"
    quoted_pattern = connection.quote(pattern)

    relation
      .where(
        "notes.title ILIKE :pattern OR #{title_sim} > 0.12 " \
        "OR note_aliases.name ILIKE :pattern " \
        "OR similarity(note_aliases.name, '#{sanitized_query}') > 0.12",
        pattern: pattern
      )
      .select(
        "notes.*, #{title_sim} AS title_similarity, " \
        "#{alias_sim} AS best_alias_similarity, " \
        "MAX(CASE WHEN note_aliases.name ILIKE #{quoted_pattern} " \
        "OR similarity(note_aliases.name, '#{sanitized_query}') > 0.12 " \
        "THEN note_aliases.name END) AS matched_alias"
      )
      .order(Arel.sql(
        "CASE WHEN notes.title ILIKE #{quoted_pattern} THEN 0 " \
        "WHEN MAX(note_aliases.name) ILIKE #{quoted_pattern} THEN 1 ELSE 2 END ASC, " \
        "GREATEST(#{title_sim}, COALESCE(#{alias_sim}, 0)) DESC, notes.title ASC"
      ))
      .limit(10)
  }

  scope :with_property, ->(key, value) {
    joins("INNER JOIN note_revisions ON note_revisions.id = notes.head_revision_id")
      .where("note_revisions.properties_data @> ?", {key => value}.to_json)
  }

  scope :with_property_in, ->(key, values) {
    joins("INNER JOIN note_revisions ON note_revisions.id = notes.head_revision_id")
      .where(
        "note_revisions.properties_data ->> ? IN (?)",
        key, values.map(&:to_s)
      )
  }

  def current_properties
    head_revision&.properties_data || {}
  end

  def properties_errors
    current_properties.dig("_errors") || {}
  end

  def properties_valid?
    properties_errors.empty?
  end

  def soft_delete!
    update!(deleted_at: Time.current)
    publish_event("note.deleted", note_id: id, slug: slug)
  end

  def restore!
    update!(deleted_at: nil)
    publish_event("note.restored", note_id: id, slug: slug)
  end

  def deleted?
    deleted_at.present?
  end

  private

  def slug_immutable
    errors.add(:slug, "cannot be changed after creation") if slug_changed?
  end

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
