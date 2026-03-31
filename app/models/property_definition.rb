class PropertyDefinition < ApplicationRecord
  VALUE_TYPES = %w[
    text long_text number boolean date datetime
    enum multi_enum url note_reference list
  ].freeze

  RESERVED_NOTE_COLUMNS = %w[title slug note_kind detected_language deleted_at].freeze
  KEY_FORMAT = /\A[a-z][a-z0-9_]{0,62}\z/

  validates :key, presence: true,
    uniqueness: {case_sensitive: false},
    format: {with: KEY_FORMAT, message: "must be lowercase alphanumeric with underscores, starting with a letter"}
  validates :value_type, presence: true, inclusion: {in: VALUE_TYPES}
  validate :key_not_reserved
  validate :config_shape_for_type

  scope :active, -> { where(archived: false) }
  scope :system_keys, -> { where(system: true) }

  def self.registry
    active.index_by(&:key)
  end

  private

  def key_not_reserved
    return if key.blank?
    errors.add(:key, "is reserved") if RESERVED_NOTE_COLUMNS.include?(key)
  end

  def config_shape_for_type
    return if value_type.blank?

    case value_type
    when "enum", "multi_enum"
      options = config&.dig("options")
      unless options.is_a?(Array) && options.all? { |o| o.is_a?(String) } && options.any?
        errors.add(:config, "must have 'options' array with at least one string for #{value_type}")
      end
    end
  end
end
