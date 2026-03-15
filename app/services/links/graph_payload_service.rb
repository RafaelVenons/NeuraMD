module Links
  class GraphPayloadService
    ROLE_LABELS = {
      "target_is_parent" => "father",
      "target_is_child" => "child",
      "same_level" => "brother"
    }.freeze

    def self.call(scope:)
      new(scope:).call
    end

    def initialize(scope:)
      @scope = scope
    end

    def call
      notes = scoped_notes.to_a
      note_ids = notes.map(&:id)
      links = load_links(note_ids)

      {
        nodes: notes.map { |note| serialize_node(note, links_by_note_id[note.id]) },
        edges: links.map { |link| serialize_edge(link) },
        meta: {
          node_count: notes.size,
          edge_count: links.size
        }
      }
    end

    private

    attr_reader :scope

    def scoped_notes
      @scoped_notes ||= scope
        .includes(:head_revision)
        .order(updated_at: :desc)
    end

    def load_links(note_ids)
      @load_links ||= NoteLink
        .includes(:tags)
        .where(src_note_id: note_ids, dst_note_id: note_ids)
        .order(:created_at)
    end

    def links_by_note_id
      @links_by_note_id ||= load_links(scoped_notes.map(&:id))
        .each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |link, hash|
          hash[link.src_note_id] << link
          hash[link.dst_note_id] << link
        end
    end

    def serialize_node(note, related_links)
      {
        id: note.id,
        slug: note.slug,
        title: note.title,
        detected_language: note.detected_language,
        updated_at: note.updated_at.iso8601,
        revision_updated_at: note.head_revision&.updated_at&.iso8601,
        degree: related_links.size,
        outgoing_count: related_links.count { |link| link.src_note_id == note.id },
        incoming_count: related_links.count { |link| link.dst_note_id == note.id }
      }
    end

    def serialize_edge(link)
      {
        id: link.id,
        source: link.src_note_id,
        target: link.dst_note_id,
        hier_role: link.hier_role,
        role_label: ROLE_LABELS[link.hier_role] || "reference",
        tags: link.tags.map do |tag|
          {
            id: tag.id,
            name: tag.name,
            color_hex: tag.color_hex
          }
        end
      }
    end
  end
end
