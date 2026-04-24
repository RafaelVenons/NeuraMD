class SeedAvatarPropertyDefinitions < ActiveRecord::Migration[8.1]
  # Delegates to Agents::AvatarPropertyDefinitions so the seed logic is shared
  # with db/seeds.rb. Fresh environments that boot via db:schema:load + db:seed
  # get the same PDs; existing environments pick them up on db:migrate.
  #
  # Raises UserOwnedCollisionError if any key is already held by a non-system
  # PD — deploy fails loudly instead of hijacking user data. Operator action
  # required to resolve (rename or promote to system).
  def up
    Agents::AvatarPropertyDefinitions.ensure!(
      logger: ->(msg) { say_with_time(msg) { } }
    )
  end

  def down
    # No-op: these PropertyDefinitions may be referenced by stored note revisions
    # (properties_data). Deleting them on rollback would orphan payloads. Manual
    # cleanup belongs in a targeted task when the migration set is truly obsolete.
  end
end
