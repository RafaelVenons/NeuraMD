class SeedTentacleYoloPropertyDefinition < ActiveRecord::Migration[8.1]
  def up
    PropertyDefinition.find_or_create_by!(key: "tentacle_yolo") do |d|
      d.value_type = "boolean"
      d.label = "Tentacle YOLO mode"
      d.description = "Quando true, WorktreeService emite .claude/settings.local.json com defaultMode=bypassPermissions no worktree do agente. Opt-in explícito por charter — Gerente/humanos NÃO devem habilitar."
      d.system = true
    end
  end

  def down
    # No-op: property definitions referenced by stored note revisions
    # cannot be deleted without orphaning revision payloads. Targeted
    # cleanup goes through a manual task if ever needed.
  end
end
