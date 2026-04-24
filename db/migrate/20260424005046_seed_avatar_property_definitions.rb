class SeedAvatarPropertyDefinitions < ActiveRecord::Migration[8.1]
  # Hats must be inlined so schema replay doesn't depend on app constants.
  # Adding a new hat = new migration, not edit-in-place. Keep in sync with
  # Agents::AvatarPalette::HATS (spec asserts).
  ALLOWED_HATS = %w[none cartola chef].freeze

  def up
    PropertyDefinition.find_or_create_by!(key: "avatar_color") do |d|
      d.value_type = "text"
      d.label = "Cor do avatar"
      d.description = "Hex (#rrggbb) da cor primária do Clawd. " \
        "Sem valor → fallback por role tag em Agents::AvatarPalette."
      d.system = true
    end

    PropertyDefinition.find_or_create_by!(key: "avatar_hat") do |d|
      d.value_type = "enum"
      d.label = "Chapéu do avatar"
      d.description = "Acessório sobre o Clawd. Catálogo extensível via nova migration."
      d.config = {"options" => ALLOWED_HATS}
      d.system = true
    end

    PropertyDefinition.find_or_create_by!(key: "avatar_variant") do |d|
      d.value_type = "text"
      d.label = "Variante do avatar"
      d.description = "Reservado pra futuras variações do Clawd (default clawd-v1)."
      d.system = true
    end
  end

  def down
    # No-op: these PropertyDefinitions may be referenced by stored note revisions
    # (properties_data). Deleting them on rollback would orphan payloads. Manual
    # cleanup belongs in a targeted task when migration set is truly obsolete.
  end
end
