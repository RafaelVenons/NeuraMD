module Tasks
  # Camada 1 do protocolo Tasks em voo. Single source of truth for
  # claim/release of iniciativa notes — replaces the Camada 0 markdown
  # table with PropertyDefinition-backed state and authority checks.
  #
  # Auth model:
  # - Only the gerente (or an explicitly delegated parent agent) can
  #   `assign_task` to a target slug. Self-claim is refused.
  # - Only the current `claimed_by` can `release_task`.
  # - Read paths (`my_tasks`, `task_history`) are open — visibility into
  #   another agent's load is non-malicious.
  #
  # Caller identity comes from `ENV["NEURAMD_AGENT_SLUG"]` set at
  # spawn by Tentacles::SessionControl + CronTickJob (see PR #33).
  module Protocol
    Unauthorized = Class.new(StandardError)
    InvalidStatus = Class.new(StandardError)
    NotClaimed = Class.new(StandardError)

    CLOSED_STATUSES = %w[completed abandoned handed_off].freeze

    # Hardcoded delegation: gerente can assign to anyone; specific
    # parent agents can assign to their direct reports. Kept here so
    # the rule set stays auditable in code review. Move to a PD or DB
    # table once the list grows beyond ~5 entries.
    DELEGATION_MAP = {
      "gerente" => :all,
      "devops" => %w[sentinela-de-deploy].freeze
    }.freeze

    module_function

    def assign(note:, agent_slug:, claim_authority:, queue_after: nil)
      raise Unauthorized, "claim_authority cannot be blank" if claim_authority.to_s.strip.empty?
      raise Unauthorized, "agent_slug cannot be blank" if agent_slug.to_s.strip.empty?
      unless can_assign?(claim_authority, agent_slug)
        raise Unauthorized, "agent #{claim_authority.inspect} is not authorized to assign tasks to #{agent_slug.inspect}"
      end

      changes = {
        "claimed_by" => agent_slug,
        "claimed_at" => Time.current.utc.iso8601,
        "claim_authority" => claim_authority,
        "closed_at" => nil,
        "closed_status" => nil
      }
      changes["queue_after"] = queue_after if queue_after.present?

      Properties::SetService.call(note: note, changes: changes, strict: true)
      note.reload
    end

    def release(note:, status:, caller_slug:, handoff_to: nil)
      raise InvalidStatus, "status must be one of #{CLOSED_STATUSES.join(", ")}" unless CLOSED_STATUSES.include?(status)
      if status == "handed_off" && handoff_to.to_s.strip.empty?
        raise InvalidStatus, "status=handed_off requires handoff_to"
      end

      props = note.current_properties
      claimed_by = props["claimed_by"]
      raise NotClaimed, "note has no claimed_by — call assign_task first" if claimed_by.to_s.strip.empty?
      raise Unauthorized, "only the current claimed_by (#{claimed_by.inspect}) can release this task" unless claimed_by == caller_slug

      changes =
        if status == "handed_off"
          {
            "claimed_by" => handoff_to,
            "claimed_at" => Time.current.utc.iso8601,
            "claim_authority" => caller_slug,
            "closed_at" => nil,
            "closed_status" => nil
          }
        else
          {
            "closed_at" => Time.current.utc.iso8601,
            "closed_status" => status
          }
        end

      Properties::SetService.call(note: note, changes: changes, strict: true)
      note.reload
    end

    # Notes currently claimed by `agent_slug` and not yet closed.
    # Ordered by claimed_at desc, then notes.updated_at desc as a
    # microsecond-precision tie-breaker (Properties::Types::Datetime
    # normalizes to second precision, so two assigns inside one second
    # would otherwise come back in arbitrary order).
    def my_tasks(agent_slug:, limit: 50)
      base_scope(agent_slug)
        .where("revs.properties_data ->> 'closed_at' IS NULL")
        .order(Arel.sql("revs.properties_data ->> 'claimed_at' DESC, notes.updated_at DESC"))
        .limit(limit)
        .to_a
    end

    # Last `limit` closed tasks for `agent_slug`. Ordered by closed_at
    # desc with notes.updated_at as the same sub-second tie-breaker.
    def task_history(agent_slug:, limit: 20)
      base_scope(agent_slug)
        .where("revs.properties_data ->> 'closed_at' IS NOT NULL")
        .order(Arel.sql("revs.properties_data ->> 'closed_at' DESC, notes.updated_at DESC"))
        .limit(limit)
        .to_a
    end

    def can_assign?(caller_slug, target_slug)
      return false if caller_slug.to_s.strip.empty?
      return false if target_slug.to_s.strip.empty?
      scope = DELEGATION_MAP[caller_slug]
      return false unless scope
      return true if scope == :all
      scope.include?(target_slug)
    end

    def base_scope(agent_slug)
      Note.active.with_latest_content
        .joins("INNER JOIN note_revisions revs ON revs.id = notes.head_revision_id")
        .where("revs.properties_data @> ?", {"claimed_by" => agent_slug}.to_json)
    end
  end
end
