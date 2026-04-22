class SeedTentacleWorkspacePropertyDefinition < ActiveRecord::Migration[8.1]
  def up
    PropertyDefinition.find_or_create_by!(key: "tentacle_workspace") do |d|
      d.value_type = "text"
      d.label = "Workspace compartilhado"
      d.description = "Nome da workspace persistida sob NEURAMD_TENTACLE_WORKSPACE_ROOT. Cada tentáculo ganha um worktree próprio em branch tentacle/<uuid>; permite múltiplos agentes trabalhando no mesmo repo em branches simultâneos."
      d.system = true
    end
  end

  def down
    # No-op: PropertyDefinition may already be referenced by stored note
    # revisions. Deleting it on rollback would orphan those payloads.
  end
end
