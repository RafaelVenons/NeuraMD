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
          extra_tags: {type: "string", description: "Comma-separated additional tags for all notes"},
          split_level: {type: "integer", description: "Heading level to fragment at. nil/absent = every heading (default). -1 = auto-detect. 0 = no fragmentation. 1+ = cut at that heading level."}
        },
        required: ["markdown", "base_tag", "import_tag"]
      )

      Section = Struct.new(:title, :level, :body_lines, :children, :parent, keyword_init: true)

      def self.call(markdown:, base_tag:, import_tag:, extra_tags: nil, split_level: nil, server_context: nil)
        return error_response("Markdown cannot be blank") if markdown.to_s.strip.blank?

        importer = new(markdown: markdown, base_tag: base_tag, import_tag: import_tag, extra_tags: extra_tags, split_level: split_level)
        importer.run
      end

      def initialize(markdown:, base_tag:, import_tag:, extra_tags:, split_level:)
        @markdown = markdown
        @base_tag = base_tag
        @import_tag = import_tag
        @extra_tags = (extra_tags.to_s.split(",").map(&:strip).reject(&:blank?))
        @split_level = split_level&.to_i
        @tag_cache = {}
        @created_notes = []
      end

      def run
        root_sections = parse_tree

        if root_sections.empty?
          # No headings found — create a single note with all content
          root_sections = [synthesize_root_section]
        end

        effective_level = resolve_split_level(root_sections)
        apply_split_level!(root_sections, effective_level)
        root_sections.each { |s| group_children!(s) }
        sections = flatten_sections(root_sections)

        ActiveRecord::Base.transaction do
          delete_previous_import!
          create_notes!(sections)
          write_contents!(sections)
        end

        data = {
          created_count: @created_notes.size,
          import_tag: @import_tag,
          split_level_used: effective_level,
          notes: @created_notes.map { |n| {slug: n[:slug], title: n[:title]} }
        }
        MCP::Tool::Response.new([{type: "text", text: data.to_json}])
      end

      private

      # ── Chapter grouping ────────────────────────────────────────────────

      MAX_CHILDREN = 20
      CHILDREN_PER_GROUP = 10

      def group_children!(section)
        section.children.each { |c| group_children!(c) }
        return if section.children.size <= MAX_CHILDREN

        groups = section.children.each_slice(CHILDREN_PER_GROUP).with_index(1).map do |batch, idx|
          part = Section.new(
            title: "Parte #{idx}",
            level: section.level + 1,
            body_lines: [],
            children: batch,
            parent: section
          )
          batch.each { |c| c.parent = part }
          part
        end
        section.children.replace(groups)
      end

      # ── Split level resolution ────────────────────────────────────────────

      def resolve_split_level(root_sections)
        return nil if @split_level.nil?
        return auto_detect_level(root_sections) if @split_level == -1
        return nil if @split_level.negative?
        @split_level
      end

      def auto_detect_level(root_sections)
        all = flatten_sections(root_sections)
        h1_count = all.count { |s| s.level == 1 }
        h2_count = all.count { |s| s.level == 2 }

        if h1_count == 1 && h2_count > 1
          2
        elsif h1_count > 1
          1
        elsif h1_count == 0 && h2_count > 1
          2
        else
          0
        end
      end

      # ── Tree collapse ─────────────────────────────────────────────────────

      def apply_split_level!(root_sections, effective_level)
        return if effective_level.nil? # nil = every heading, no collapse

        if effective_level.zero?
          collapse_all_into_root!(root_sections)
        else
          root_sections.each { |s| collapse_children_below!(s, effective_level) }
        end
      end

      def collapse_all_into_root!(sections)
        return if sections.empty?
        root = sections.first
        body = rebuild_markdown_body(root)
        root.body_lines.replace(body)
        root.children.clear
        sections.replace([root])
      end

      def collapse_children_below!(section, level)
        section.children.each { |child| collapse_children_below!(child, level) }

        remaining = []
        section.children.each do |child|
          if child.level > level
            section.body_lines << "" if section.body_lines.any? && section.body_lines.last&.strip&.present?
            section.body_lines << "#{"#" * child.level} #{child.title}"
            section.body_lines.concat(child.body_lines)
          else
            remaining << child
          end
        end
        section.children.replace(remaining)
      end

      def rebuild_markdown_body(section)
        lines = section.body_lines.dup
        section.children.each do |child|
          lines << "" if lines.any? && lines.last&.strip&.present?
          lines << "#{"#" * child.level} #{child.title}"
          lines.concat(rebuild_markdown_body(child))
        end
        lines
      end

      def synthesize_root_section
        title = @base_tag.tr("-", " ").titleize
        body = @markdown.lines.map(&:chomp)
        Section.new(title: title, level: 1, body_lines: body, children: [], parent: nil)
      end

      # ── Parsing ────────────────────────────────────────────────────────────

      def parse_tree
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

        root_sections
      end

      def flatten_sections(sections)
        result = []
        sections.each do |section|
          result << section
          result.concat(flatten_sections(section.children))
        end
        result
      end

      # ── Import operations ──────────────────────────────────────────────────

      def delete_previous_import!
        imported_notes = Note.joins(:tags).where(tags: {name: @import_tag.downcase})
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

        body = section.body_lines.dup
        body.pop while body.last&.strip&.empty?
        body.shift while body.first&.strip&.empty?

        lines.concat(body) if body.any?

        if section.children.any?
          lines << "" if lines.any?
          section.children.each_with_index do |child, i|
            child_note = child.instance_variable_get(:@note)
            lines << "#{i + 1}. [[#{child.title}|c:#{child_note.id}]]"
          end
        end

        # Sequential navigation between siblings
        siblings = section.parent&.children
        if siblings && siblings.size > 1
          idx = siblings.index(section)
          nav = []
          if idx && idx > 0
            prev_note = siblings[idx - 1].instance_variable_get(:@note)
            nav << "Anterior: [[#{siblings[idx - 1].title}|n:#{prev_note.id}]]"
          end
          if idx && idx < siblings.size - 1
            next_note = siblings[idx + 1].instance_variable_get(:@note)
            nav << "Proximo: [[#{siblings[idx + 1].title}|n:#{next_note.id}]]"
          end
          if nav.any?
            lines << ""
            lines << "---"
            lines << nav.join(" | ")
          end
        end

        content = lines.join("\n")
        content.presence || "(sem conteudo textual)"
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
