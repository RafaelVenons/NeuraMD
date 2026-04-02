# frozen_string_literal: true

require "mcp"

module Mcp
  module Tools
    class UpdateNoteTool < MCP::Tool
      extend NoteFinder

      tool_name "update_note"
      description "Update an existing NeuraMD note: change content, rename title, add/remove tags, set aliases, append wikilinks. Follows slug redirects and aliases."

      input_schema(
        type: "object",
        properties: {
          slug: {type: "string", description: "Current slug of the note (follows redirects)"},
          title: {type: "string", description: "New title (triggers rename with slug redirect)"},
          content_markdown: {type: "string", description: "New markdown content (replaces current, creates checkpoint revision)"},
          add_tags: {type: "string", description: "Comma-separated tags to add (created if they don't exist)"},
          remove_tags: {type: "string", description: "Comma-separated tags to remove"},
          append_links: {type: "string", description: "Comma-separated links to append as wikilinks. Format: 'Display|role:uuid' (role: f/c/b or omit). Appended to current content and saved via checkpoint."},
          set_properties: {type: "string", description: "JSON object of property key-value pairs to set. Use null value to remove a property. Example: '{\"status\":\"published\",\"priority\":3}'"},
          set_aliases: {type: "string", description: 'JSON array of alias strings. Replaces all current aliases. Example: \'["Cardio", "Heart Notes"]\''}

        },
        required: ["slug"]
      )

      def self.call(slug:, title: nil, content_markdown: nil, add_tags: nil, remove_tags: nil, append_links: nil, set_properties: nil, set_aliases: nil, server_context: nil)
        note = find_note(slug)
        return error_response("Note not found: #{slug}") unless note

        has_changes = [title, content_markdown, add_tags, remove_tags, append_links, set_properties, set_aliases].any?(&:present?)
        return error_response("Nothing to update — provide title, content_markdown, add_tags, remove_tags, append_links, set_properties, or set_aliases") unless has_changes

        if title.present? && title.strip != note.title
          Notes::RenameService.call(note: note, new_title: title.strip)
        end

        if content_markdown.present?
          Notes::CheckpointService.call(
            note: note,
            content: content_markdown,
            author: nil,
            accepted_ai_request: nil
          )
        end

        if append_links.present? && content_markdown.blank?
          current_body = note.reload.head_revision&.content_markdown.to_s
          wikilink_lines = build_wikilink_lines(append_links)
          new_body = [current_body.rstrip, "", wikilink_lines].join("\n")
          Notes::CheckpointService.call(
            note: note,
            content: new_body,
            author: nil,
            accepted_ai_request: nil
          )
        end

        manage_tags!(note, add_tags, remove_tags)
        set_properties!(note, set_properties) if set_properties.present?
        set_aliases!(note, set_aliases) if set_aliases.present?

        note.reload
        data = {
          updated: true,
          slug: note.slug,
          title: note.title,
          id: note.id,
          tags: note.tags.pluck(:name),
          aliases: note.note_aliases.pluck(:name),
          properties: note.current_properties
        }

        MCP::Tool::Response.new([{type: "text", text: data.to_json}])
      end

      def self.manage_tags!(note, add_tags, remove_tags)
        if add_tags.present?
          tag_names = add_tags.to_s.split(",").map(&:strip).reject(&:blank?)
          tag_names.each do |name|
            tag = Tag.find_or_create_by!(name: name.downcase) do |t|
              t.tag_scope = "note"
            end
            note.tags << tag unless note.tags.include?(tag)
          end
        end

        if remove_tags.present?
          tag_names = remove_tags.to_s.split(",").map(&:strip).reject(&:blank?)
          tags_to_remove = note.tags.where(name: tag_names.map(&:downcase))
          note.tags.delete(tags_to_remove)
        end
      end

      def self.set_properties!(note, properties_json)
        changes = JSON.parse(properties_json)
        Properties::SetService.call(note: note, changes: changes, strict: false)
      rescue JSON::ParserError => e
        raise "Invalid JSON for set_properties: #{e.message}"
      end

      def self.set_aliases!(note, aliases_json)
        aliases = JSON.parse(aliases_json)
        raise "set_aliases must be a JSON array" unless aliases.is_a?(Array)
        Aliases::SetService.call(note: note, aliases: aliases)
      rescue JSON::ParserError => e
        raise "Invalid JSON for set_aliases: #{e.message}"
      end

      def self.build_wikilink_lines(append_links_string)
        # Format: "Display|role:uuid,Display2|uuid" → "[[Display|role:uuid]]\n[[Display2|uuid]]"
        append_links_string.split(",").map(&:strip).reject(&:blank?).map do |entry|
          "[[#{entry}]]"
        end.join("\n")
      end

      def self.error_response(message)
        MCP::Tool::Response.new([{type: "text", text: message}], error: true)
      end
    end
  end
end
