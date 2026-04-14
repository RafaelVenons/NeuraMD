# frozen_string_literal: true

require "mcp"

module Mcp
  module Tools
    class ManagePropertyTool < MCP::Tool
      extend NoteFinder

      tool_name "manage_property"
      description "Get, set, or delete a single typed property on a NeuraMD note. Creates a checkpoint revision on set/delete. Follows slug redirects and aliases."

      VALID_OPERATIONS = %w[get set delete].freeze

      input_schema(
        type: "object",
        properties: {
          slug: {type: "string", description: "Slug or alias of the note (follows redirects)"},
          operation: {type: "string", description: "One of: get, set, delete", enum: VALID_OPERATIONS},
          key: {type: "string", description: "Property key as registered in PropertyDefinition"},
          value: {type: "string", description: "JSON-encoded value for set (e.g. '\"draft\"', '3', 'true', '[\"a\",\"b\"]'). Ignored for get/delete."}
        },
        required: ["slug", "operation", "key"]
      )

      def self.call(slug:, operation:, key:, value: nil, server_context: nil)
        return error_response("Invalid operation: #{operation}. Must be one of: #{VALID_OPERATIONS.join(", ")}") unless VALID_OPERATIONS.include?(operation)

        note = find_note(slug)
        return error_response("Note not found: #{slug}") unless note

        case operation
        when "get"
          perform_get(note, key)
        when "set"
          perform_set(note, key, value)
        when "delete"
          perform_delete(note, key)
        end
      end

      def self.perform_get(note, key)
        properties = note.current_properties
        json_response(
          slug: note.slug,
          key: key,
          value: properties[key],
          present: properties.key?(key)
        )
      end

      def self.perform_set(note, key, raw_value)
        return error_response("value is required for set") if raw_value.nil?

        parsed = parse_value(raw_value)
        Properties::SetService.call(note: note, changes: {key => parsed}, strict: true)

        note.reload
        json_response(
          slug: note.slug,
          key: key,
          value: note.current_properties[key],
          operation: "set"
        )
      rescue Properties::SetService::UnknownKeyError => e
        error_response(e.message)
      rescue Properties::SetService::ValidationError => e
        error_response(e.message)
      rescue JSON::ParserError => e
        error_response("Invalid JSON for value: #{e.message}")
      end

      def self.perform_delete(note, key)
        Properties::SetService.call(note: note, changes: {key => nil}, strict: true)
        note.reload
        json_response(
          slug: note.slug,
          key: key,
          operation: "delete",
          present: note.current_properties.key?(key)
        )
      rescue Properties::SetService::UnknownKeyError => e
        error_response(e.message)
      end

      def self.parse_value(raw)
        return raw unless raw.is_a?(String)
        JSON.parse(raw)
      rescue JSON::ParserError
        raw
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
