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
        # Eager-load the merge-target lookup paths up front so
        # suggest_merge_target can pick from in-memory associations
        # instead of issuing find_by + dst_note/src_note round-trips
        # per anemic note (was ~6 queries per match before).
        scope = Note.active.includes(
          :head_revision,
          :tags,
          {active_outgoing_links: :dst_note},
          {active_incoming_links: :src_note}
        )
        scope = scope.joins(:tags).where(tags: {name: tag.downcase}) if tag.present?

        anemic = scope.find_each.filter_map { |note|
          content = note.head_revision&.content_markdown.to_s
          lines = content_lines(content)
          next if lines >= max_lines

          {
            slug: note.slug,
            title: note.title,
            content_lines: lines,
            tags: note.tags.map(&:name),
            merge_target: suggest_merge_target(note)
          }
        }.first(limit)

        data = {anemic_notes: anemic, count: anemic.size, threshold: max_lines}
        MCP::Tool::Response.new([{type: "text", text: data.to_json}])
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
