module Agents
  # Single source of truth for the Clawd avatar PropertyDefinitions. Called
  # from both the seed data migration (for environments that get there via
  # db:migrate) and db/seeds.rb (for fresh environments that bootstrap via
  # db:schema:load + db:seed — data migrations do not replay there).
  #
  # Idempotency model: find-or-init, assign expected shape, save!. Safe to
  # run repeatedly. Refuses to overwrite user-created PDs (system: false)
  # with the same key — those signal name collision, not a migration we own.
  module AvatarPropertyDefinitions
    UserOwnedCollisionError = Class.new(StandardError)

    # Inlined here instead of delegating to Agents::AvatarPalette so the data
    # contract (what goes into PropertyDefinition.config) is explicit at the
    # seed site. Schema replay + seed run do not depend on app constants
    # behaving a specific way. Keep in sync with AvatarPalette::HATS /
    # AvatarPalette::VARIANTS (specs assert equality).
    ALLOWED_HATS = %w[none cartola chef].freeze
    ALLOWED_VARIANTS = %w[clawd-v1].freeze

    # Hex triplet (#rgb) or sextet (#rrggbb), case-insensitive. Matches
    # Graph::NoteSerializer::HEX_COLOR_PATTERN — serializer keeps its check
    # as belt-and-suspenders for legacy rows written before this validator
    # existed.
    HEX_COLOR_PATTERN = "\\A#(?:[0-9A-Fa-f]{3}|[0-9A-Fa-f]{6})\\z".freeze

    SEEDS = [
      {
        key: "avatar_color",
        value_type: "text",
        label: "Cor do avatar",
        description: "Hex (#rgb ou #rrggbb) da cor primária do Clawd. " \
          "Sem valor → fallback por role tag em Agents::AvatarPalette. " \
          "Valores fora do formato são rejeitados no write path.",
        config: {"pattern" => HEX_COLOR_PATTERN}
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
        value_type: "enum",
        label: "Variante do avatar",
        description: "Família do Clawd (clawd-v1 inicial). " \
          "Variantes futuras entram via nova migration.",
        config: {"options" => ALLOWED_VARIANTS}
      }
    ].freeze

    def self.ensure!(logger: nil)
      collisions = SEEDS.map { |attrs| attrs.fetch(:key) }.select do |key|
        existing = PropertyDefinition.find_by(key: key)
        existing && !existing.system
      end

      if collisions.any?
        raise UserOwnedCollisionError,
          "Refusing to overwrite user-owned PropertyDefinition(s): #{collisions.join(", ")}. " \
          "These keys are reserved as system-owned by Agents::AvatarPropertyDefinitions. " \
          "Manual action required: rename the conflicting row(s) or promote them to system:true."
      end

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
          logger&.call("avatar_property_definitions: correcting #{attrs[:key].inspect} (was: #{pd.changes.inspect})")
        end
        pd.save!
      end
    end
  end
end
