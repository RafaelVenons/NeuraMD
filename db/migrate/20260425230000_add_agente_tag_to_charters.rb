class AddAgenteTagToCharters < ActiveRecord::Migration[8.1]
  # Backfills the `agente` tag on charters that were tagged before the
  # serializer's switch from `agente-team` to `agente` as the agent
  # discriminator. Delegates to Agents::AgenteTagBackfill so the same
  # backfill runs from db/seeds.rb on fresh environments.
  def up
    Agents::AgenteTagBackfill.ensure!(
      logger: ->(msg) { say_with_time(msg) { } }
    )
  end

  def down
    # No-op: removing the tag here would orphan production data the team
    # already relies on. Targeted cleanup belongs in a follow-up migration
    # if this discriminator is ever retired.
  end
end
