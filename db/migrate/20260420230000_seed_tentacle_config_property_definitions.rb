class SeedTentacleConfigPropertyDefinitions < ActiveRecord::Migration[8.1]
  def up
    PropertyDefinition.find_or_create_by!(key: "tentacle_cwd") do |d|
      d.value_type = "text"
      d.label = "Diretório de trabalho"
      d.description = "Caminho absoluto do repo onde o tentáculo deve operar. Whitelistado em SpawnChildTentacleTool."
      d.system = true
    end

    PropertyDefinition.find_or_create_by!(key: "tentacle_initial_prompt") do |d|
      d.value_type = "long_text"
      d.label = "Prompt inicial"
      d.description = "Mensagem escrita na stdin da sessão após o boot do Claude. Cap 2KB."
      d.system = true
    end
  end

  def down
    # No-op: these PropertyDefinitions may already exist or may be referenced by
    # stored note revisions (properties_data). Deleting them on rollback would
    # orphan revision payloads and could remove definitions this migration did
    # not create. If manual cleanup is required, run it in a targeted task.
  end
end
