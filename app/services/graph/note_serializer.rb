module Graph
  class NoteSerializer
    EXCERPT_LIMIT = 180

    def self.call(note)
      new(note).call
    end

    def initialize(note)
      @note = note
    end

    def call
      {
        id: note.id,
        slug: note.slug,
        title: note.title,
        excerpt: excerpt,
        updated_at: note.updated_at&.iso8601,
        created_at: note.created_at&.iso8601
      }
    end

    private

    attr_reader :note

    def excerpt
      note.head_revision&.search_preview_text(limit: EXCERPT_LIMIT)
    end
  end
end
