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
      ActiveRecord::Base.transaction do
        handle_collisions!(logger: logger)

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

    # Detects user-owned (system: false) PDs sharing a reserved key. Two paths:
    #
    # - Default (safe): raise UserOwnedCollisionError. Deploy fails loud,
    #   operator decides what to do with the data manually.
    #
    # - Opt-in via ENV["AVATAR_SEED_RENAME_LEGACY"]="1": rename colliders to
    #   `<key>_legacy_<epoch>` within the same transaction so the canonical
    #   key is free for the system-owned row. The legacy row keeps its
    #   config/value_type/data intact — only the key changes. `save(validate:
    #   false)` because the PD has RESERVED_SYSTEM_KEYS guard that would
    #   reject the original key for non-system rows (the row was created
    #   before the guard existed).
    #
    # Opt-in because renaming mutates data operators may not have authorized.
    # Both paths are transactional — if any step in ensure! fails, rename rolls
    # back with the rest.
    def self.handle_collisions!(logger:)
      collisions = SEEDS.map { |attrs| attrs.fetch(:key) }.filter_map do |key|
        existing = PropertyDefinition.find_by(key: key)
        existing if existing && !existing.system
      end
      return if collisions.empty?

      if rename_legacy_enabled?
        rename_timestamp = Time.current.to_i
        collisions.each do |pd|
          new_key = "#{pd.key}_legacy_#{rename_timestamp}"
          logger&.call("avatar_property_definitions: renaming legacy user-owned PD " \
            "#{pd.key.inspect} → #{new_key.inspect} (id=#{pd.id})")
          pd.key = new_key
          pd.save!(validate: false)
        end
      else
        keys = collisions.map(&:key)
        raise UserOwnedCollisionError,
          "Refusing to overwrite user-owned PropertyDefinition(s): #{keys.join(", ")}. " \
          "These keys are reserved as system-owned by Agents::AvatarPropertyDefinitions. " \
          "Options: (a) rename/remove the conflicting row(s) and re-run; " \
          "(b) promote them to system:true if the data should live under the new contract; " \
          "(c) set AVATAR_SEED_RENAME_LEGACY=1 to auto-rename to '<key>_legacy_<timestamp>' " \
          "(data preserved, key suffixed — note-level properties_data under the old key " \
          "will still match the new system PD)."
      end
    end

    def self.rename_legacy_enabled?
      value = ENV["AVATAR_SEED_RENAME_LEGACY"].to_s.downcase
      %w[1 true yes on].include?(value)
    end
  end
end
