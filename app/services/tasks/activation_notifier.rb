module Tasks
  # Camada 1 hook: when an `activate_tentacle_session` is requested by
  # any path other than the gerente, drop a heads-up in the gerente's
  # inbox so coordination stays observable. Includes the target's
  # current open tasks so the gerente can immediately spot
  # double-claims or stale work.
  #
  # Best-effort: failures are logged but never propagate — activation
  # itself must not be blocked by the notification side-effect.
  module ActivationNotifier
    GERENTE_SLUG = "gerente"
    UNKNOWN_REQUESTOR = "unknown".freeze
    OPEN_TASKS_SAMPLE_LIMIT = 10

    module_function

    def notify_if_external(target_note:, requested_by:)
      caller = requested_by.to_s.strip.presence
      return if caller == GERENTE_SLUG

      gerente = Note.active.find_by(slug: GERENTE_SLUG)
      return unless gerente
      return if gerente.id == target_note.id

      from_note = resolve_from_note(caller, fallback: gerente, gerente_id: gerente.id)
      return unless from_note

      AgentMessages::Sender.call(
        from: from_note,
        to: gerente,
        content: build_content(target_note: target_note, requested_by: caller)
      )
    rescue StandardError => e
      Rails.logger.error("[tasks] activation notify failed: #{e.class}: #{e.message}")
    end

    def resolve_from_note(caller, fallback:, gerente_id:)
      return target_or_nil(fallback, gerente_id) if caller.nil?
      candidate = Note.active.find_by(slug: caller)
      target_or_nil(candidate || fallback, gerente_id)
    end

    def target_or_nil(note, gerente_id)
      return nil if note.nil?
      # Sender refuses self-send. If we'd end up sending from gerente
      # to gerente, skip — there's no useful inbox entry.
      return nil if note.id == gerente_id
      note
    end

    def build_content(target_note:, requested_by:)
      open_tasks = Tasks::Protocol.my_tasks(agent_slug: target_note.slug, limit: OPEN_TASKS_SAMPLE_LIMIT)
      list_lines =
        if open_tasks.empty?
          "(nenhuma)"
        else
          open_tasks.map { |n| "- #{n.title} (slug: #{n.slug})" }.join("\n")
        end

      label = requested_by.presence || UNKNOWN_REQUESTOR
      <<~MSG.strip
        Sessão de #{target_note.slug.inspect} foi acordada por #{label.inspect} em #{Time.current.utc.iso8601}.

        Tasks abertas atribuídas a #{target_note.slug}:
        #{list_lines}
      MSG
    end
  end
end
