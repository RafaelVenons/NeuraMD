module Links
  # Parses wiki-link markup from markdown content and returns an array of link descriptors.
  #
  # Parses wiki-links like [[Display|role:uuid]] into link descriptors.
  # The vocabulary of accepted role tokens lives in NoteLink::Roles::TOKEN_TO_SEMANTIC;
  # tokens outside that allow-list fall through to hier_role: nil (plain link).
  class ExtractService
    ROLE_MAP = NoteLink::Roles::TOKEN_TO_SEMANTIC

    UUID_RE = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i
    SLUG_RE = /[a-z0-9]+(?:-[a-z0-9]+)*/
    WIKILINK_RE = /(?<!!)\[\[(?:[^\]|]+)\|(?:(?<role>[a-z]+):)?(?<id>#{UUID_RE}|#{SLUG_RE})(?:#(?<heading>[a-z0-9_-]+)|\^(?<block>[a-zA-Z0-9-]+))?\]\]/i

    def self.call(content)
      new(content).call
    end

    def initialize(content)
      @content = content.to_s
    end

    def call
      @content
        .scan(WIKILINK_RE)
        .map { |role_prefix, id_or_slug, heading, block| build_link(role_prefix, id_or_slug, heading, block) }
        .compact
        .each_with_object({}) do |link, by_destination|
          current = by_destination[link[:dst_note_id]]
          if current
            merge_fragments!(current, link)
            if replace_link?(current, link)
              current[:hier_role] = link[:hier_role]
            end
          else
            by_destination[link[:dst_note_id]] = link
          end
        end
        .values
    end

    private

    def build_link(role_prefix, id_or_slug, heading, block)
      role_key = role_prefix.to_s.downcase
      heading_slug = heading.presence
      block_id = block.presence

      uuid = resolve_id(id_or_slug)
      return nil unless uuid

      link = {
        dst_note_id: uuid,
        hier_role: ROLE_MAP[role_key]
      }
      link[:heading_slugs] = [heading_slug] if heading_slug
      link[:block_ids] = [block_id] if block_id
      link
    end

    def resolve_id(id_or_slug)
      value = id_or_slug.to_s
      return value.downcase if value.match?(/\A#{UUID_RE}\z/)

      Note.where(slug: value).pick(:id)
    end

    def merge_fragments!(current, candidate)
      h_slugs = Array(current[:heading_slugs]) | Array(candidate[:heading_slugs])
      current[:heading_slugs] = h_slugs if h_slugs.any?

      b_ids = Array(current[:block_ids]) | Array(candidate[:block_ids])
      current[:block_ids] = b_ids if b_ids.any?
    end

    def replace_link?(current, candidate)
      return true if current.nil?

      candidate_score(candidate) >= candidate_score(current)
    end

    def candidate_score(link)
      link[:hier_role].present? ? 1 : 0
    end
  end
end
