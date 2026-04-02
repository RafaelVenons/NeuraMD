module Links
  # Updates the display text of wikilinks pointing to a renamed note.
  #
  # When a note is renamed, all notes that link to it still contain the old
  # title as display text: [[Old Title|uuid]]. This service finds those notes,
  # replaces the display text with the new title, and creates checkpoints to
  # preserve revision history.
  #
  # Wikilink format: [[Display Text|[role:]UUID]]
  # Roles are preserved: f: (parent), c: (child), b: (sibling)
  class DisplayTextUpdateService
    UUID_RE = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i

    def self.call(renamed_note_id:, new_title:)
      new(renamed_note_id:, new_title:).call
    end

    def initialize(renamed_note_id:, new_title:)
      @renamed_note_id = renamed_note_id.to_s.downcase
      @new_title = new_title
    end

    def call
      return if @new_title.blank?

      pattern = build_pattern(@renamed_note_id)

      src_notes = Note.active
        .joins(:outgoing_links)
        .where(note_links: {dst_note_id: @renamed_note_id, active: true})
        .distinct

      src_notes.find_each do |src_note|
        update_note_content(src_note, pattern)
      end
    end

    private

    def build_pattern(uuid)
      escaped_uuid = Regexp.escape(uuid)
      /\[\[([^\]|]+)\|((?:[a-z]+:)?#{escaped_uuid}(?:#[a-z0-9_-]+|\^[a-zA-Z0-9-]+)?)\]\]/i
    end

    def update_note_content(src_note, pattern)
      revision = src_note.head_revision
      return unless revision

      content = revision.content_markdown
      return unless content.match?(pattern)

      updated = content.gsub(pattern) { "[[#{@new_title}|#{$2}]]" }
      return if updated == content

      Notes::CheckpointService.call(
        note: src_note,
        content: updated,
        author: nil
      )
    end
  end
end
