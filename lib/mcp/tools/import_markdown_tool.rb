# frozen_string_literal: true

require "mcp"

module Mcp
  module Tools
    class ImportMarkdownTool < MCP::Tool
      include ::DomainEvents

      tool_name "import_markdown"
      description "Import a markdown file into NeuraMD notes. Each heading becomes a note. Parent-child links are created via wikilinks. Previous import batch (by import_tag) is cleaned before reimport."

      input_schema(
        type: "object",
        properties: {
          markdown: {type: "string", description: "Full markdown content to import"},
          base_tag: {type: "string", description: "Base tag for all imported notes (e.g. 'shop', 'plan')"},
          import_tag: {type: "string", description: "Technical tag for reimport cleanup (e.g. 'shop-import')"},
          extra_tags: {type: "string", description: "Comma-separated additional tags for all notes"}
        },
        required: ["markdown", "base_tag", "import_tag"]
      )

      Section = Struct.new(:title, :level, :body_lines, :children, :parent, keyword_init: true)

      def self.call(markdown:, base_tag:, import_tag:, extra_tags: nil, server_context: nil)
        return error_response("Markdown cannot be blank") if markdown.to_s.strip.blank?

        importer = new(markdown: markdown, base_tag: base_tag, import_tag: import_tag, extra_tags: extra_tags)
        importer.run
      end

      def initialize(markdown:, base_tag:, import_tag:, extra_tags:)
        @markdown = markdown
        @base_tag = base_tag
        @import_tag = import_tag
        @extra_tags = (extra_tags.to_s.split(",").map(&:strip).reject(&:blank?))
        @tag_cache = {}
        @created_notes = []
      end

      def run
        sections = parse_sections
        return self.class.error_response("No headings found in markdown") if sections.empty?

        ActiveRecord::Base.transaction do
          delete_previous_import!
          create_notes!(sections)
          write_contents!(sections)
        end

        data = {
          created_count: @created_notes.size,
          import_tag: @import_tag,
          notes: @created_notes.map { |n| {slug: n[:slug], title: n[:title]} }
        }
        MCP::Tool::Response.new([{type: "text", text: data.to_json}])
      end

      private

      def parse_sections
        lines = @markdown.lines.map(&:chomp)
        root_sections = []
        stack = []

        lines.each do |line|
          if line.match?(/\A#+\s/)
            level = line[/\A(#+)/, 1].length
            title = line.sub(/\A#+\s*/, "").strip
            section = Section.new(title: title, level: level, body_lines: [], children: [], parent: nil)

            while stack.any? && stack.last.level >= level
              stack.pop
            end

            if stack.any?
              section.parent = stack.last
              stack.last.children << section
            else
              root_sections << section
            end

            stack << section
          elsif stack.any?
            stack.last.body_lines << line
          end
        end

        flatten_sections(root_sections)
      end

      def flatten_sections(sections)
        result = []
        sections.each do |section|
          result << section
          result.concat(flatten_sections(section.children))
        end
        result
      end

      def delete_previous_import!
        imported_notes = Note.joins(:tags).where(tags: {name: @import_tag})
        note_ids = imported_notes.pluck(:id)
        return if note_ids.empty?

        revision_ids = NoteRevision.where(note_id: note_ids).pluck(:id)
        Note.where(id: note_ids).update_all(head_revision_id: nil)
        NoteTag.where(note_id: note_ids).delete_all
        SlugRedirect.where(note_id: note_ids).delete_all
        NoteLink.where(src_note_id: note_ids).or(NoteLink.where(dst_note_id: note_ids)).delete_all
        NoteRevision.where(id: revision_ids).delete_all
        Note.where(id: note_ids).delete_all
      end

      def create_notes!(sections)
        sections.each do |section|
          note = Note.create!(title: section.title, note_kind: "markdown")
          publish_event("note.created", note_id: note.id, slug: note.slug, title: note.title)
          section.instance_variable_set(:@note, note)
          attach_tags!(section)
          @created_notes << {slug: note.slug, title: note.title, note: note}
        end
      end

      def write_contents!(sections)
        sections.each do |section|
          note = section.instance_variable_get(:@note)
          content = build_content(section)

          revision = note.note_revisions.create!(
            content_markdown: content,
            revision_kind: :checkpoint
          )
          note.update!(head_revision_id: revision.id)

          Links::SyncService.call(src_note: note, revision: revision, content: content)
        end
      end

      def build_content(section)
        lines = []
        note = section.instance_variable_get(:@note)

        # Clean body: strip trailing blank lines
        body = section.body_lines.dup
        body.pop while body.last&.strip&.empty?
        body.shift while body.first&.strip&.empty?

        # Body content
        lines.concat(body) if body.any?

        # Child index as wikilinks
        if section.children.any?
          lines << "" if lines.any?
          section.children.each_with_index do |child, i|
            child_note = child.instance_variable_get(:@note)
            lines << "#{i + 1}. [[#{child.title}|c:#{child_note.id}]]"
          end
        end

        lines.join("\n")
      end

      def attach_tags!(section)
        note = section.instance_variable_get(:@note)
        tag_names = [@base_tag, @import_tag]
        tag_names.concat(@extra_tags)
        tag_names << "#{@base_tag}-h#{section.level}"
        tag_names << "#{@base_tag}-raiz" if section.parent.nil?
        tag_names << "#{@base_tag}-estrutura" if section.children.any?

        tag_names.uniq.each do |name|
          tag = ensure_tag!(name)
          NoteTag.find_or_create_by!(note: note, tag: tag)
        end
      end

      def ensure_tag!(name)
        @tag_cache[name] ||= Tag.find_or_create_by!(name: name.downcase) do |tag|
          tag.tag_scope = "note"
        end
      end

      def self.error_response(message)
        MCP::Tool::Response.new([{type: "text", text: message}], error: true)
      end
    end
  end
end
