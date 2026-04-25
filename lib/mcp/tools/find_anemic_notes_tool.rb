# frozen_string_literal: true

require "mcp"

module Mcp
  module Tools
    class FindAnemicNotesTool < MCP::Tool
      tool_name "find_anemic_notes"
      description "Find 'anemic' notes (fewer than N content lines, default 10). Returns notes with suggested merge targets."

      input_schema(
        type: "object",
        properties: {
          max_lines: {type: "integer", description: "Threshold: notes with fewer content lines are anemic (default: 10)"},
          tag: {type: "string", description: "Optional: only check notes with this tag"},
          limit: {type: "integer", description: "Max results (default: 30)"}
        }
      )

      def self.call(max_lines: 10, tag: nil, limit: 30, server_context: nil)
        # Two-phase to avoid two opposite footguns:
        #   1. The original code did N+1 in suggest_merge_target — one
        #      find_by + .dst_note/.src_note pair per anemic match.
        #   2. Naive eager-loading the link graph in the outer scan
        #      preloads incoming/outgoing links + neighbour notes for
        #      EVERY active note, even non-anemic ones with hundreds
        #      of links. In a workspace where most notes are not
        #      anemic but heavily linked, that is much worse than
        #      the N+1 it replaces (large preload queries + memory).
        # Phase 1 streams the cheap scan (head_revision + tags only)
        # and stops as soon as `limit` anemic candidates are gathered.
        # Phase 2 reloads ONLY those candidates with the link
        # associations needed by suggest_merge_target. Cost scales
        # with the candidate count, not the workspace size.
        candidates = collect_anemic_candidates(max_lines: max_lines, tag: tag, limit: limit)
        enriched = enrich_with_links(candidates.map(&:first))

        anemic = candidates.map do |(note, lines)|
          rich = enriched[note.id] || note
          {
            slug: rich.slug,
            title: rich.title,
            content_lines: lines,
            tags: rich.tags.map(&:name),
            merge_target: suggest_merge_target(rich)
          }
        end

        data = {anemic_notes: anemic, count: anemic.size, threshold: max_lines}
        MCP::Tool::Response.new([{type: "text", text: data.to_json}])
      end

      def self.collect_anemic_candidates(max_lines:, tag:, limit:)
        scope = Note.active.includes(:head_revision, :tags)
        scope = scope.joins(:tags).where(tags: {name: tag.downcase}) if tag.present?

        candidates = []
        scope.find_each do |note|
          content = note.head_revision&.content_markdown.to_s
          lines = content_lines(content)
          next if lines >= max_lines

          candidates << [note, lines]
          break if candidates.size >= limit
        end
        candidates
      end

      def self.enrich_with_links(notes)
        return {} if notes.empty?

        Note.where(id: notes.map(&:id))
          .includes(
            :head_revision,
            :tags,
            {active_outgoing_links: :dst_note},
            {active_incoming_links: :src_note}
          )
          .index_by(&:id)
      end

      # Picks the best merge candidate from the in-memory eager-loaded
      # associations: parent first (outgoing target_is_parent), then
      # reverse-parent (incoming target_is_child), then the first
      # incoming neighbor as a generic linked_from. Each branch reads
      # only fields that came along with the eager load — no DB hit.
      def self.suggest_merge_target(note)
        outgoing = note.active_outgoing_links.to_a
        parent_link = outgoing.find { |l| l.hier_role == "target_is_parent" && l.dst_note && !l.dst_note.deleted? }
        if parent_link
          return {slug: parent_link.dst_note.slug, title: parent_link.dst_note.title, relation: "parent"}
        end

        incoming = note.active_incoming_links.to_a
        reverse_parent = incoming.find { |l| l.hier_role == "target_is_child" && l.src_note && !l.src_note.deleted? }
        if reverse_parent
          return {slug: reverse_parent.src_note.slug, title: reverse_parent.src_note.title, relation: "parent"}
        end

        any_incoming = incoming.find { |l| l.src_note && !l.src_note.deleted? }
        if any_incoming
          return {slug: any_incoming.src_note.slug, title: any_incoming.src_note.title, relation: "linked_from"}
        end

        nil
      end

      def self.content_lines(content)
        content.lines
          .map(&:strip)
          .reject { |l|
            l.empty? || l.start_with?("---", "<!--") ||
            l.match?(/\A(Origem|Profundidade|Trilha|Pai|Linha-guia|Temas|Relacionadas|Indice estrutural):/i)
          }
          .size
      end
    end
  end
end
