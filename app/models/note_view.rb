class NoteView < ApplicationRecord
  DISPLAY_TYPES = %w[table card list].freeze
  BUILTIN_SORT_FIELDS = %w[title created_at updated_at].freeze

  validates :name, presence: true
  validates :display_type, inclusion: {in: DISPLAY_TYPES}
  validate :sort_config_shape
  validate :columns_shape

  scope :ordered, -> { order(:position, :name) }

  def parsed_filter
    @parsed_filter ||= Search::Dsl::Parser.call(filter_query.to_s)
  end

  def sort_field
    sort_config&.dig("field") || "updated_at"
  end

  def sort_direction
    sort_config&.dig("direction") == "asc" ? :asc : :desc
  end

  private

  def sort_config_shape
    return if sort_config.blank? || sort_config == {}
    unless sort_config.is_a?(Hash) && sort_config["field"].is_a?(String)
      errors.add(:sort_config, "must have a 'field' string key")
    end
    if sort_config["direction"].present? && !%w[asc desc].include?(sort_config["direction"])
      errors.add(:sort_config, "direction must be 'asc' or 'desc'")
    end
  end

  def columns_shape
    unless columns.is_a?(Array) && columns.all? { |c| c.is_a?(String) }
      errors.add(:columns, "must be an array of strings")
    end
  end
end
