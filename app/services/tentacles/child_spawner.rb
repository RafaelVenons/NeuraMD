module Tentacles
  class ChildSpawner
    include ::DomainEvents

    class BlankTitle < StandardError; end

    Result = Struct.new(:child, :revision, :body, keyword_init: true)

    def self.call(parent:, title:, description: nil, extra_tags: nil)
      new(parent: parent, title: title, description: description, extra_tags: extra_tags).call
    end

    def initialize(parent:, title:, description:, extra_tags:)
      @parent      = parent
      @title       = title.to_s.strip
      @description = description.to_s.strip
      @extra_tags  = extra_tags
    end

    def call
      raise BlankTitle, "title cannot be blank" if @title.empty?

      body = compose_body
      child = Note.create!(title: @title, note_kind: "markdown")
      revision = child.note_revisions.create!(content_markdown: body, revision_kind: :checkpoint)
      child.update!(head_revision_id: revision.id)
      publish_event("note.created", note_id: child.id, slug: child.slug, title: child.title)

      Links::SyncService.call(src_note: child, revision: revision, content: body)
      apply_tags!(child)

      Result.new(child: child.reload, revision: revision, body: body)
    end

    private

    def compose_body
      link_line = "[[#{@parent.title}|f:#{@parent.id}]]"
      body = +link_line
      body << "\n\n" << @description unless @description.empty?
      body << "\n\n## Todos\n\n"
      body
    end

    def apply_tags!(note)
      names = ["tentacle"] + @extra_tags.to_s.split(",").map(&:strip).reject(&:blank?)
      names.uniq.each do |name|
        tag = Tag.find_or_create_by!(name: name.downcase) { |t| t.tag_scope = "note" }
        note.tags << tag unless note.tags.include?(tag)
      end
    end
  end
end
