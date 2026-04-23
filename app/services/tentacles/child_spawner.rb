module Tentacles
  class ChildSpawner
    include ::DomainEvents

    class BlankTitle < StandardError; end
    class DualTarget < StandardError; end

    Result = Struct.new(:child, :revision, :body, keyword_init: true)

    def self.call(parent:, title:, description: nil, extra_tags: nil, cwd: nil, initial_prompt: nil, workspace: nil)
      new(
        parent: parent,
        title: title,
        description: description,
        extra_tags: extra_tags,
        cwd: cwd,
        initial_prompt: initial_prompt,
        workspace: workspace
      ).call
    end

    def initialize(parent:, title:, description:, extra_tags:, cwd:, initial_prompt:, workspace:)
      @parent         = parent
      @title          = title.to_s.strip
      @description    = description.to_s.strip
      @extra_tags     = extra_tags
      @cwd            = cwd.presence
      @initial_prompt = initial_prompt.presence
      @workspace      = workspace.presence
    end

    def call
      raise BlankTitle, "title cannot be blank" if @title.empty?
      if @cwd && @workspace
        raise DualTarget, "cannot set both cwd and workspace — pick one"
      end

      body = compose_body
      child = Note.create!(title: @title, note_kind: "markdown")
      revision = child.note_revisions.create!(content_markdown: body, revision_kind: :checkpoint)
      child.update!(head_revision_id: revision.id)
      publish_event("note.created", note_id: child.id, slug: child.slug, title: child.title)

      Links::SyncService.call(src_note: child, revision: revision, content: body)
      apply_tags!(child)
      revision = apply_boot_config!(child.reload) || revision

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

    def apply_boot_config!(note)
      changes = {}
      changes["tentacle_cwd"] = @cwd if @cwd
      changes["tentacle_initial_prompt"] = @initial_prompt if @initial_prompt
      changes["tentacle_workspace"] = @workspace if @workspace
      return nil if changes.empty?

      Properties::SetService.call(note: note, changes: changes)
    end
  end
end
