module AgentMessages
  class Inbox
    DEFAULT_LIMIT = 50

    def self.for(note, limit: DEFAULT_LIMIT, only_pending: false)
      new(note, limit: limit, only_pending: only_pending).call
    end

    def initialize(note, limit:, only_pending:)
      @note         = note
      @limit        = limit.to_i.clamp(1, 200)
      @only_pending = only_pending
    end

    def call
      scope = AgentMessage.inbox(@note).includes(:from_note)
      scope = scope.where(delivered_at: nil) if @only_pending
      scope.limit(@limit)
    end

    def self.mark_all_delivered!(note, now: Time.current)
      AgentMessage
        .inbox(note)
        .where(delivered_at: nil)
        .update_all(delivered_at: now, updated_at: now)
    end

    def self.mark_delivered!(note, ids:, now: Time.current)
      return 0 if ids.blank?

      AgentMessage
        .inbox(note)
        .where(id: ids, delivered_at: nil)
        .update_all(delivered_at: now, updated_at: now)
    end
  end
end
