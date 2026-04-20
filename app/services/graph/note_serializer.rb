module Graph
  class NoteSerializer
    EXCERPT_LIMIT = 180

    def self.call(note, incoming_link_count: 0, outgoing_link_count: 0, promise_titles: [])
      new(
        note,
        incoming_link_count:,
        outgoing_link_count:,
        promise_titles:
      ).call
    end

    def initialize(note, incoming_link_count:, outgoing_link_count:, promise_titles:)
      @note = note
      @incoming_link_count = incoming_link_count
      @outgoing_link_count = outgoing_link_count
      @promise_titles = promise_titles
    end

    def call
      {
        id: note.id,
        slug: note.slug,
        title: note.title,
        excerpt: excerpt,
        updated_at: note.updated_at&.iso8601,
        created_at: note.created_at&.iso8601,
        incoming_link_count: incoming_link_count,
        outgoing_link_count: outgoing_link_count,
        has_links: has_links?,
        promise_titles: promise_titles,
        promise_count: promise_titles.size,
        has_promises: promise_titles.any?,
        node_type: node_type,
        properties: properties
      }
    end

    private

    attr_reader :note, :incoming_link_count, :outgoing_link_count, :promise_titles

    def excerpt
      note.head_revision&.search_preview_text(limit: EXCERPT_LIMIT)
    end

    def has_links?
      incoming_link_count.positive? || outgoing_link_count.positive?
    end

    def node_type
      names = tag_names
      return "tentacle" if names.include?("tentacle")
      return "root" if names.any? { |n| n.end_with?("-raiz") }
      return "structure" if names.any? { |n| n.end_with?("-estrutura") }

      "leaf"
    end

    def tag_names
      note.tags.map(&:name)
    end

    def properties
      (note.head_revision&.properties_data || {}).except("_errors")
    end
  end
end
