# frozen_string_literal: true

require "mcp"

module Mcp
  module Tools
    class PatchNoteTool < MCP::Tool
      extend NoteFinder

      tool_name "patch_note"
      description "Patch a NeuraMD note's markdown at a specific heading. Supports append, prepend, and replace_section operations. Creates a checkpoint revision."

      VALID_OPERATIONS = %w[append prepend replace_section].freeze

      input_schema(
        type: "object",
        properties: {
          slug: {type: "string", description: "Slug of the note (follows redirects and aliases)"},
          heading: {type: "string", description: "Exact heading text to anchor the patch (case-insensitive, whitespace-tolerant)"},
          operation: {type: "string", enum: VALID_OPERATIONS, description: "append (end of section), prepend (right after heading line), or replace_section (body only, keeps heading)"},
          content: {type: "string", description: "Markdown content to insert or replace with"}
        },
        required: ["slug", "heading", "operation", "content"]
      )

      def self.call(slug:, heading:, operation:, content:, server_context: nil)
        return error_response("Invalid operation: #{operation}. Must be one of: #{VALID_OPERATIONS.join(", ")}") unless VALID_OPERATIONS.include?(operation)

        note = find_note(slug)
        return error_response("Note not found: #{slug}") unless note

        body = note.head_revision&.content_markdown.to_s
        lines = body.lines

        target = find_heading_range(lines, heading)
        unless target
          available = scan_headings(lines).map { |h| h[:text] }
          return error_response("Heading not found: #{heading.strip}. Available: #{available.join(" | ")}")
        end

        new_body = apply_patch(lines, target, operation, content)

        Notes::CheckpointService.call(
          note: note,
          content: new_body,
          author: nil,
          accepted_ai_request: nil
        )

        json_response(
          patched: true,
          slug: note.slug,
          operation: operation,
          heading: target[:text],
          heading_line: target[:line]
        )
      end

      # Scan markdown for # headings. Returns [{line:, level:, text:}] in order.
      def self.scan_headings(lines)
        out = []
        lines.each_with_index do |raw, idx|
          stripped = raw.chomp.strip
          next unless (m = stripped.match(/\A(\#{1,6})\s+(.+?)\s*\z/))
          out << {line: idx, level: m[1].length, text: m[2].strip}
        end
        out
      end

      # Find line range [start_line, end_line) for the section owned by the
      # first heading whose text matches (case-insensitive, stripped). The
      # section extends until the next heading of equal-or-shallower level, or EOF.
      def self.find_heading_range(lines, target_text)
        norm = target_text.to_s.strip.downcase
        headings = scan_headings(lines)
        idx = headings.find_index { |h| h[:text].downcase == norm }
        return nil unless idx

        head = headings[idx]
        next_head = headings[(idx + 1)..].find { |h| h[:level] <= head[:level] }
        end_line = next_head ? next_head[:line] : lines.size

        {line: head[:line], level: head[:level], text: head[:text], end_line: end_line}
      end

      def self.apply_patch(lines, target, operation, content)
        heading_line = target[:line]
        end_line = target[:end_line]
        content_lines = content.to_s.end_with?("\n") ? content.lines : (content.to_s + "\n").lines

        case operation
        when "append"
          # Insert before the next heading. Trim trailing blanks inside the
          # section, then add a single blank separator.
          section_end = trim_trailing_blanks(lines, heading_line + 1, end_line)
          prefix = lines[0...section_end]
          suffix = lines[end_line..] || []
          separator = needs_blank_before?(prefix) ? ["\n"] : []
          (prefix + separator + content_lines + ["\n"] + suffix).join
        when "prepend"
          # Insert right after the heading line, with a blank separator.
          head_slice = lines[0..heading_line]
          rest = lines[(heading_line + 1)..] || []
          rest_trimmed = drop_leading_blanks(rest)
          (head_slice + ["\n"] + content_lines + ["\n"] + rest_trimmed).join
        when "replace_section"
          head_slice = lines[0..heading_line]
          suffix = lines[end_line..] || []
          (head_slice + ["\n"] + content_lines + ["\n"] + suffix).join
        end
      end

      def self.trim_trailing_blanks(lines, from, to)
        i = to
        i -= 1 while i > from && lines[i - 1].to_s.strip.empty?
        i
      end

      def self.drop_leading_blanks(lines)
        lines.drop_while { |l| l.to_s.strip.empty? }
      end

      def self.needs_blank_before?(lines)
        return false if lines.empty?
        !lines.last.to_s.strip.empty?
      end

      def self.json_response(data)
        MCP::Tool::Response.new([{type: "text", text: data.to_json}])
      end

      def self.error_response(message)
        MCP::Tool::Response.new([{type: "text", text: message}], error: true)
      end
    end
  end
end
