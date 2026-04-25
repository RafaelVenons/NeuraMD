class SeedTasksProtocolPropertyDefinitions < ActiveRecord::Migration[8.1]
  def up
    PropertyDefinition.find_or_create_by!(key: "claimed_by") do |d|
      d.value_type = "text"
      d.label = "Atribuído a"
      d.description = "Slug do agente que está executando esta task. Setado pelo MCP tool assign_task; nunca pelo próprio agente."
      d.system = true
    end

    PropertyDefinition.find_or_create_by!(key: "claimed_at") do |d|
      d.value_type = "datetime"
      d.label = "Atribuída em"
      d.description = "ISO8601 do momento da atribuição. Setado junto com claimed_by por assign_task."
      d.system = true
    end

    PropertyDefinition.find_or_create_by!(key: "closed_at") do |d|
      d.value_type = "datetime"
      d.label = "Encerrada em"
      d.description = "ISO8601 do momento da liberação. Setado por release_task. Tasks com closed_at != nil saem do my_tasks."
      d.system = true
    end

    PropertyDefinition.find_or_create_by!(key: "closed_status") do |d|
      d.value_type = "enum"
      d.label = "Status final"
      d.description = "Resultado da execução. completed = entregue; abandoned = desistido sem entrega; handed_off = passado pra outro agente."
      d.system = true
      d.config = {"options" => %w[completed abandoned handed_off]}
    end

    PropertyDefinition.find_or_create_by!(key: "queue_after") do |d|
      d.value_type = "text"
      d.label = "Aguardando"
      d.description = "Slug de outra nota-iniciativa que esta task deve esperar terminar antes de executar."
      d.system = true
    end

    PropertyDefinition.find_or_create_by!(key: "claim_authority") do |d|
      d.value_type = "text"
      d.label = "Atribuído por"
      d.description = "Slug do agente que executou o assign_task. Trilha de auditoria — gerente na maioria; agente-pai operacional para sub-agentes."
      d.system = true
    end
  end

  def down
    # No-op: these PropertyDefinitions may already be referenced by stored
    # note revisions (properties_data). Deleting them on rollback would
    # orphan revision payloads. If manual cleanup is required, run it in
    # a targeted task.
  end
end
