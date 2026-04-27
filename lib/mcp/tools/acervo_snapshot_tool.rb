# frozen_string_literal: true

require "mcp"

module Mcp
  module Tools
    # Single-call situational-awareness snapshot of the acervo. Composed
    # of slices that an agent typically runs back-to-back at the start
    # of a session: what changed recently, what looks anemic and might
    # need consolidation, which tags are dominant, and (when called
    # through the gateway with a bound token) how full the caller's
    # own inbox is.
    class AcervoSnapshotTool < MCP::Tool
      DEFAULT_SINCE_HOURS = 24
      DEFAULT_LIMIT = 10
      MAX_LIMIT = 50
      ANEMIC_THRESHOLD_LINES = 10

      tool_name "acervo_snapshot"
      description <<~DESC.strip
        Single-call snapshot of the acervo state. Returns recent_changes
        within since_hours, an anemic_notes summary (count + sample),
        top_tags by note count, and — when invoked through the gateway
        with an agent-bound token — inbox_pending for the caller's
        agent_note. Cheap composition of existing queries; intended for
        "open a session, see what's up" rather than deep audits.
      DESC

      input_schema(
        type: "object",
        properties: {
          since_hours: {type: "integer", description: "Recent-change window in hours (default #{DEFAULT_SINCE_HOURS}, max 720)"},
          limit_per_section: {type: "integer", description: "Max items per section (default #{DEFAULT_LIMIT}, max #{MAX_LIMIT})"}
        }
      )

      def self.call(since_hours: DEFAULT_SINCE_HOURS, limit_per_section: DEFAULT_LIMIT, server_context: nil, **_)
        since_hours = since_hours.to_i.clamp(1, 720)
        limit = limit_per_section.to_i.clamp(1, MAX_LIMIT)
        cutoff = since_hours.hours.ago

        payload = {
          generated_at: Time.current.iso8601,
          since_hours: since_hours,
          recent_changes: recent_changes(cutoff: cutoff, limit: limit),
          anemic_notes: anemic_summary(limit: limit),
          top_tags: top_tags(limit: limit)
        }

        token = server_context && server_context[:mcp_token]
        if token && token.respond_to?(:agent_note) && token.agent_note
          note = token.agent_note
          payload[:inbox_pending] = {
            agent_slug: note.slug,
            count: AgentMessage.inbox(note).where(delivered_at: nil).count
          }
        end

        MCP::Tool::Response.new([{type: "text", text: payload.to_json}])
      end

      def self.recent_changes(cutoff:, limit:)
        Note.active
          .joins("INNER JOIN note_revisions head_rev ON head_rev.id = notes.head_revision_id")
          .includes(:tags)
          .select("notes.*, head_rev.created_at AS head_revision_created_at")
          .where("head_rev.created_at > ?", cutoff)
          .order("head_rev.created_at DESC")
          .limit(limit)
          .map { |n| {slug: n.slug, title: n.title, tags: n.tags.map(&:name), changed_at: n.head_revision_created_at.iso8601} }
      end

      def self.anemic_summary(limit:)
        sample = []
        total = 0
        Note.active.includes(:head_revision).find_each do |note|
          lines = content_lines(note.head_revision&.content_markdown.to_s)
          next if lines >= ANEMIC_THRESHOLD_LINES
          total += 1
          sample << {slug: note.slug, title: note.title, content_lines: lines} if sample.size < limit
        end
        {count: total, threshold_lines: ANEMIC_THRESHOLD_LINES, sample: sample}
      end

      def self.top_tags(limit:)
        Tag.left_joins(:note_tags)
          .group("tags.id", "tags.name")
          .order(Arel.sql("COUNT(note_tags.note_id) DESC"))
          .limit(limit)
          .pluck("tags.name", Arel.sql("COUNT(note_tags.note_id)"))
          .map { |name, count| {name: name, note_count: count.to_i} }
      end

      def self.content_lines(content)
        content.lines
          .map(&:strip)
          .reject { |l| l.empty? || l.start_with?("---", "<!--") }
          .size
      end
    end
  end
end
