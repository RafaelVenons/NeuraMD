class PropertyDefinition < ApplicationRecord
  VALUE_TYPES = %w[
    text long_text number boolean date datetime
    enum multi_enum url note_reference list
  ].freeze

  RESERVED_NOTE_COLUMNS = %w[title slug note_kind detected_language deleted_at].freeze
  # Keys owned by system seeders (Agents::AvatarPropertyDefinitions,
  # the tentacle_cwd/initial_prompt/workspace migrations). Blocked for
  # user-created (system: false) PDs so future deploys cannot trip on a
  # hijacked key. Seeders bypass by setting `system: true`.
  RESERVED_SYSTEM_KEYS = %w[
    avatar_color avatar_hat avatar_variant
    tentacle_cwd tentacle_initial_prompt tentacle_workspace
    claimed_by claimed_at closed_at closed_status queue_after claim_authority
  ].freeze
  KEY_FORMAT = /\A[a-z][a-z0-9_]{0,62}\z/

  # Cap on user-supplied regex patterns in config["pattern"]. Bounds compile
  # time + match time alongside the per-regex timeout applied at validation
  # (Properties::Types::Text.safe_regexp). Longer patterns have exponential
  # backtracking surface — reject at create/update.
  PATTERN_MAX_LENGTH = 200

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
    errors.add(:key, "is reserved for system seeders") if !system && RESERVED_SYSTEM_KEYS.include?(key)
  end

  def config_shape_for_type
    return if value_type.blank?

    case value_type
    when "enum", "multi_enum"
      options = config&.dig("options")
      unless options.is_a?(Array) && options.all? { |o| o.is_a?(String) } && options.any?
        errors.add(:config, "must have 'options' array with at least one string for #{value_type}")
      end
    when "text", "long_text"
      validate_text_pattern
    end
  end

  def validate_text_pattern
    pattern = config&.dig("pattern")
    return if pattern.nil?

    unless pattern.is_a?(String)
      errors.add(:config, "pattern must be a string")
      return
    end
    if pattern.length > PATTERN_MAX_LENGTH
      errors.add(:config, "pattern is too long (max #{PATTERN_MAX_LENGTH} characters)")
      return
    end
    begin
      Regexp.new(pattern)
    rescue RegexpError => e
      errors.add(:config, "pattern is not a valid regular expression: #{e.message}")
    end
  end
end
