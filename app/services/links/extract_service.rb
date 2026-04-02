module Links
  # Parses wiki-link markup from markdown content and returns an array of link descriptors.
  #
  # Supported formats:
  #   [[Display Text|uuid]]        → hier_role: nil
  #   [[Display Text|f:uuid]]      → hier_role: "target_is_parent"  (Father)
  #   [[Display Text|c:uuid]]      → hier_role: "target_is_child"   (Child)
  #   [[Display Text|b:uuid]]      → hier_role: "same_level"        (Brother)
  #
  # Returns array of { dst_note_id: uuid, hier_role: string_or_nil }.
  # The DB allows only one note_link per destination note, so repeated references to the
  # same UUID collapse into a single link. If any occurrence has an explicit role prefix,
  # that semantic role wins over plain references.
  class ExtractService
    ROLE_MAP = {
      "f" => "target_is_parent",
      "c" => "target_is_child",
      "b" => "same_level"
    }.freeze

    UUID_RE = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i
    WIKILINK_RE = /\[\[(?:[^\]|]+)\|(?:(?<role>[a-z]+):)?(?<uuid>#{UUID_RE})(?:#(?<heading>[a-z0-9_-]+))?\]\]/i

    def self.call(content)
      new(content).call
    end

    def initialize(content)
      @content = content.to_s
    end

    def call
      @content
        .scan(WIKILINK_RE)
        .map { |role_prefix, uuid, heading| build_link(role_prefix, uuid, heading) }
        .each_with_object({}) do |link, by_destination|
          current = by_destination[link[:dst_note_id]]
          if current
            merge_heading_slugs!(current, link)
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

    def build_link(role_prefix, uuid, heading)
      role_key = role_prefix.to_s.downcase
      heading_slug = heading.presence

      link = {
        dst_note_id: uuid.downcase,
        hier_role: ROLE_MAP[role_key]
      }
      link[:heading_slugs] = [heading_slug] if heading_slug
      link
    end

    def merge_heading_slugs!(current, candidate)
      slugs = Array(current[:heading_slugs]) | Array(candidate[:heading_slugs])
      if slugs.any?
        current[:heading_slugs] = slugs
      end
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
