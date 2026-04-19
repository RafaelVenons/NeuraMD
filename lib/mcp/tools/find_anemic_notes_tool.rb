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
        scope = Note.active.includes(:head_revision, :tags)
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

      def self.suggest_merge_target(note)
        parent_link = note.outgoing_links.active.find_by(hier_role: "target_is_parent")
        if parent_link&.dst_note
          return {slug: parent_link.dst_note.slug, title: parent_link.dst_note.title, relation: "parent"}
        end

        reverse_parent = note.incoming_links.active.find_by(hier_role: "target_is_child")
        if reverse_parent&.src_note
          return {slug: reverse_parent.src_note.slug, title: reverse_parent.src_note.title, relation: "parent"}
        end

        incoming = note.incoming_links.active.includes(:src_note).first
        if incoming&.src_note
          return {slug: incoming.src_note.slug, title: incoming.src_note.title, relation: "linked_from"}
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
