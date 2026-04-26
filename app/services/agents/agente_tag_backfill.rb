module Agents
  # Ensures charters carry the `agente` discriminator tag that
  # Graph::NoteSerializer reads in `agent?` to publish the avatar payload.
  # Charters are notes carrying any `agente-{role}` tag (e.g. `agente-uxui`,
  # `agente-rubi`); the umbrella tag `agente-team` and its descendants
  # (`agente-team-template`, `agente-team-raiz`) are NOT charters and stay
  # untouched.
  #
  # Production was backfilled via MCP on 2026-04-23 (17 charters). This
  # service exists so fresh environments (db:schema:load + db:seed) and any
  # future replay of `db:migrate` converge to the same state.
  #
  # Idempotent — re-runs are no-ops thanks to the unique
  # `(note_id, tag_id)` index on `note_tags`.
  module AgenteTagBackfill
    AGENT_TAG_NAME = "agente".freeze

    # Frozen at ship time. Anything matching `agente-%` AND NOT `agente-team%`
    # is treated as a charter. The `agente-team*` exclusion covers the
    # umbrella, `agente-team-template`, and `agente-team-raiz` in one rule.
    ROLE_TAG_PATTERN = "agente-%".freeze
    EXCLUDED_TAG_PATTERN = "agente-team%".freeze

    def self.ensure!(logger: nil)
      ActiveRecord::Base.transaction do
        agente_tag = Tag.find_or_create_by!(name: AGENT_TAG_NAME)

        candidate_ids = Note.joins(:tags)
          .where("tags.name LIKE ?", ROLE_TAG_PATTERN)
          .where.not("tags.name LIKE ?", EXCLUDED_TAG_PATTERN)
          .distinct
          .pluck(:id)

        already_tagged = NoteTag
          .where(tag_id: agente_tag.id, note_id: candidate_ids)
          .pluck(:note_id)
          .to_set

        missing_ids = candidate_ids.reject { |id| already_tagged.include?(id) }

        if missing_ids.any?
          NoteTag.insert_all!(
            missing_ids.map { |nid| {note_id: nid, tag_id: agente_tag.id} }
          )
        end

        logger&.call(
          "agente_tag_backfill: candidates=#{candidate_ids.size} " \
          "already_tagged=#{already_tagged.size} added=#{missing_ids.size}"
        )
      end
    end
  end
end
