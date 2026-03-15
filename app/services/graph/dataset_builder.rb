require "set"

module Graph
  class DatasetBuilder
    def self.call(scope:)
      new(scope:).call
    end

    def initialize(scope:)
      @scope = scope
    end

    def call
      notes = load_notes
      note_ids = notes.map(&:id).to_set
      links = load_links(note_ids)
      link_ids = links.map(&:id)
      note_tag_rows = NoteTag.where(note_id: note_ids.to_a).pluck(:note_id, :tag_id)
      link_tag_rows = LinkTag.where(note_link_id: link_ids).pluck(:note_link_id, :tag_id)
      tag_ids = (note_tag_rows.map(&:last) + link_tag_rows.map(&:last)).uniq
      tags = Tag.where(id: tag_ids).order(:name)

      {
        notes: notes.map { |note| NoteSerializer.call(note) },
        links: links.map { |link| LinkSerializer.call(link) },
        tags: tags.map { |tag| TagSerializer.call(tag) },
        noteTags: note_tag_rows.map { |note_id, tag_id| {note_id:, tag_id:} },
        linkTags: link_tag_rows.map { |note_link_id, tag_id| {note_link_id:, tag_id:} },
        meta: {
          generated_at: Time.current.iso8601,
          note_count: notes.size,
          link_count: links.size,
          tag_count: tags.size
        }
      }
    end

    private

    attr_reader :scope

    def load_notes
      scope
        .includes(:head_revision, :tags)
        .order(updated_at: :desc)
        .to_a
    end

    def load_links(note_ids)
      seen_pairs = Set.new

      NoteLink
        .includes(:tags)
        .where(src_note_id: note_ids.to_a, dst_note_id: note_ids.to_a)
        .order(:created_at)
        .each_with_object([]) do |link, memo|
          unless note_ids.include?(link.src_note_id) && note_ids.include?(link.dst_note_id)
            Rails.logger.warn("graph.dataset_builder dropped link=#{link.id} reason=missing_note")
            next
          end

          pair_key = [link.src_note_id, link.dst_note_id]
          if seen_pairs.include?(pair_key)
            Rails.logger.warn("graph.dataset_builder dropped link=#{link.id} reason=duplicate_pair")
            next
          end

          seen_pairs << pair_key
          memo << link
        end
    end
  end
end
