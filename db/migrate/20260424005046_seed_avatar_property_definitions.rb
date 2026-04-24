class SeedAvatarPropertyDefinitions < ActiveRecord::Migration[8.1]
  # Hats must be inlined so schema replay doesn't depend on app constants.
  # Adding a new hat = new migration, not edit-in-place. Keep in sync with
  # Agents::AvatarPalette::HATS (spec asserts).
  ALLOWED_HATS = %w[none cartola chef].freeze

  SEEDS = [
    {
      key: "avatar_color",
      value_type: "text",
      label: "Cor do avatar",
      description: "Hex (#rrggbb) da cor primária do Clawd. " \
        "Sem valor → fallback por role tag em Agents::AvatarPalette.",
      config: {}
    },
    {
      key: "avatar_hat",
      value_type: "enum",
      label: "Chapéu do avatar",
      description: "Acessório sobre o Clawd. Catálogo extensível via nova migration.",
      config: {"options" => ALLOWED_HATS}
    },
    {
      key: "avatar_variant",
      value_type: "text",
      label: "Variante do avatar",
      description: "Reservado pra futuras variações do Clawd (default clawd-v1).",
      config: {}
    }
  ].freeze

  # Strong idempotency: find-or-init, assign the full expected shape, save!.
  # This overwrites pre-existing rows (user-created PDs with the same key, or
  # stale archived rows) so every environment converges on the same contract.
  # Without this, `find_or_create_by!` would leave mismatched rows untouched
  # and environments diverge silently.
  def up
    SEEDS.each do |attrs|
      pd = PropertyDefinition.find_or_initialize_by(key: attrs.fetch(:key))
      pd.assign_attributes(
        value_type: attrs.fetch(:value_type),
        label: attrs.fetch(:label),
        description: attrs.fetch(:description),
        config: attrs.fetch(:config),
        system: true,
        archived: false
      )
      if pd.persisted? && pd.changed?
        say_with_time("correcting PropertyDefinition #{attrs[:key].inspect} " \
                      "(was: #{pd.changes.inspect})") { pd.save! }
      else
        pd.save!
      end
    end
  end

  def down
    # No-op: these PropertyDefinitions may be referenced by stored note revisions
    # (properties_data). Deleting them on rollback would orphan payloads. Manual
    # cleanup belongs in a targeted task when migration set is truly obsolete.
  end
end
