# frozen_string_literal: true

require "mcp"
require "base64"

module Mcp
  module Tools
    class ReadNoteTool < MCP::Tool
      extend NoteFinder

      BACKLINK_LIMIT_DEFAULT = 100
      BACKLINK_LIMIT_MAX = 200
      NONE_TOKEN = "none"

      tool_name "read_note"
      description "Read a NeuraMD note by slug or alias. Returns full content, tags, aliases, and links. Each link carries both `role` (semantic name, e.g. target_is_child) and `role_token` (1-char token: f/c/b/p/d/v/x or null). Follows slug redirects and aliases."

      input_schema(
        type: "object",
        properties: {
          slug: {type: "string", description: "The note slug (URL identifier)"},
          backlink_roles: {
            type: "string",
            description: "Optional CSV of 1-char role tokens to filter backlinks (e.g. 'p,x'). Use 'none' for backlinks without role. Unknown tokens are silently ignored."
          },
          backlink_limit: {
            type: "integer",
            description: "Max backlinks to return (default #{BACKLINK_LIMIT_DEFAULT}, capped at #{BACKLINK_LIMIT_MAX}). Values ≤0 fall back to default."
          },
          backlink_cursor: {
            type: "string",
            description: "Opaque cursor from a previous response (backlinks_next_cursor) to resume pagination."
          },
          backlinks_updated_since: {
            type: "string",
            description: "ISO8601 timestamp. Returns only backlinks whose updated_at is ≥ since."
          }
        },
        required: ["slug"]
      )

      def self.call(
        slug:,
        backlink_roles: nil,
        backlink_limit: nil,
        backlink_cursor: nil,
        backlinks_updated_since: nil,
        server_context: nil
      )
        note = find_note(slug)
        return error_response("Note not found: #{slug}") unless note

        outgoing = note.active_outgoing_links.includes(:dst_note).map do |link|
          {
            target_slug: link.dst_note.slug,
            target_title: link.dst_note.title,
            role: link.hier_role,
            role_token: role_token(link.hier_role),
            direction: "outgoing"
          }
        end

        backlinks_result = fetch_backlinks(
          note: note,
          roles: backlink_roles,
          limit: backlink_limit,
          cursor: backlink_cursor,
          updated_since: backlinks_updated_since
        )
        return backlinks_result if backlinks_result.is_a?(MCP::Tool::Response)

        unlinked_mentions = Mentions::UnlinkedService.call(note: note).mentions.map do |m|
          {
            source_slug: m.source_note.slug,
            source_title: m.source_note.title,
            matched_term: m.matched_term,
            snippets: m.snippets
          }
        end

        headings = note.note_headings.order(:position).map do |h|
          {text: h.text, slug: h.slug, level: h.level}
        end

        blocks = note.note_blocks.order(:position).map do |b|
          {block_id: b.block_id, content: b.content, block_type: b.block_type}
        end

        data = {
          slug: note.slug,
          title: note.title,
          aliases: note.note_aliases.pluck(:name),
          body: note.head_revision&.content_markdown.to_s,
          tags: note.tags.pluck(:name),
          properties: note.current_properties,
          headings: headings,
          blocks: blocks,
          links: outgoing,
          backlinks: backlinks_result[:items],
          backlinks_next_cursor: backlinks_result[:next_cursor],
          backlinks_has_more: backlinks_result[:has_more],
          unlinked_mentions: unlinked_mentions,
          created_at: note.created_at.iso8601,
          updated_at: note.updated_at.iso8601
        }

        MCP::Tool::Response.new([{type: "text", text: data.to_json}])
      end

      def self.role_token(hier_role)
        NoteLink::Roles::SEMANTIC_TO_TOKEN[hier_role]
      end

      def self.fetch_backlinks(note:, roles:, limit:, cursor:, updated_since:)
        scope = note.active_incoming_links.includes(:src_note)

        role_filter = parse_role_filter(roles)
        scope = scope.where(hier_role: role_filter) if role_filter

        if updated_since.present?
          begin
            since_time = Time.iso8601(updated_since.to_s)
          rescue ArgumentError
            return error_response("Invalid backlinks_updated_since (ISO8601 expected): #{updated_since}")
          end
          scope = scope.where("note_links.updated_at >= ?", since_time)
        end

        if cursor.present?
          cursor_time, cursor_id = decode_cursor(cursor)
          return error_response("Invalid backlink_cursor") unless cursor_time && cursor_id

          scope = scope.where(
            "note_links.updated_at < ? OR (note_links.updated_at = ? AND note_links.id < ?)",
            cursor_time, cursor_time, cursor_id
          )
        end

        effective_limit = clamp_limit(limit)
        rows = scope.order(updated_at: :desc, id: :desc).limit(effective_limit + 1).to_a
        has_more = rows.length > effective_limit
        rows = rows.first(effective_limit)

        items = rows.map do |link|
          {
            source_slug: link.src_note.slug,
            source_title: link.src_note.title,
            role: link.hier_role,
            role_token: role_token(link.hier_role),
            direction: "incoming"
          }
        end
        next_cursor = has_more && rows.any? ? encode_cursor(rows.last.updated_at, rows.last.id) : nil

        {items: items, next_cursor: next_cursor, has_more: has_more}
      end

      def self.parse_role_filter(csv)
        return nil if csv.nil?
        tokens = csv.to_s.split(",").map(&:strip).reject(&:empty?)
        return nil if tokens.empty?

        # Unknown tokens are ignored (not converted). 'none' is the explicit sentinel
        # for NULL hier_role. If all tokens are unknown, the result is an empty filter,
        # which Rails interprets as "no matches" — preserving the user's intent to filter.
        tokens.each_with_object([]) do |token, acc|
          if token == NONE_TOKEN
            acc << nil
          elsif (sem = NoteLink::Roles::TOKEN_TO_SEMANTIC[token])
            acc << sem
          end
        end
      end

      def self.clamp_limit(limit)
        return BACKLINK_LIMIT_DEFAULT unless limit.is_a?(Integer)
        return BACKLINK_LIMIT_DEFAULT if limit <= 0
        [limit, BACKLINK_LIMIT_MAX].min
      end

      def self.encode_cursor(updated_at, id)
        Base64.strict_encode64("#{updated_at.iso8601(6)}|#{id}")
      end

      def self.decode_cursor(encoded)
        raw = Base64.strict_decode64(encoded.to_s)
        ts, id = raw.split("|", 2)
        return [nil, nil] if ts.blank? || id.blank?
        [Time.iso8601(ts), id]
      rescue ArgumentError
        [nil, nil]
      end

      def self.error_response(message)
        MCP::Tool::Response.new([{type: "text", text: message}], error: true)
      end
    end
  end
end
