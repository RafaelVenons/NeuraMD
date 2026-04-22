module Neuramd
  module Exporter
    module Collectors
      # Snapshot counts from the acervo. Queried on every scrape via AR,
      # so the pool should have at least one connection reserved (see
      # the systemd unit env defaults).
      class Notes < Base
        def collect
          [
            {
              name: "neuramd_note_count",
              type: "gauge",
              help: "Total non-deleted notes in the acervo.",
              samples: [{value: Note.active.count}]
            },
            {
              name: "neuramd_note_deleted_count",
              type: "gauge",
              help: "Soft-deleted notes still in the database.",
              samples: [{value: Note.where.not(deleted_at: nil).count}]
            },
            {
              name: "neuramd_agent_messages_pending",
              type: "gauge",
              help: "Agent messages persisted but not yet delivered.",
              samples: [{value: AgentMessage.where(delivered_at: nil).count}]
            }
          ]
        end
      end
    end
  end
end
