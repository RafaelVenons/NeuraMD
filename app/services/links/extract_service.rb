module Links
  # Parses wiki-link markup from markdown content and returns an array of link descriptors.
  #
  # Supported formats:
  #   [[Display Text|uuid]]        → hier_role: nil
  #   [[Display Text|f:uuid]]      → hier_role: "target_is_parent"  (Father)
  #   [[Display Text|c:uuid]]      → hier_role: "target_is_child"   (Child)
  #   [[Display Text|b:uuid]]      → hier_role: "same_level"        (Brother)
  #
  # Returns array of { dst_note_id: uuid, hier_role: string_or_nil }
  # Deduplicates by (dst_note_id, hier_role) — same UUID with different roles = two links.
  class ExtractService
    ROLE_MAP = {
      "f" => "target_is_parent",
      "c" => "target_is_child",
      "b" => "same_level"
    }.freeze

    UUID_RE = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i
    WIKILINK_RE = /\[\[(?:[^\]|]+)\|(?<role>[fcb]:)?(?<uuid>#{UUID_RE})\]\]/i

    def self.call(content)
      new(content).call
    end

    def initialize(content)
      @content = content.to_s
    end

    def call
      @content
        .scan(WIKILINK_RE)
        .map { |role_prefix, uuid| {dst_note_id: uuid.downcase, hier_role: ROLE_MAP[role_prefix&.chomp(":")]} }
        .uniq { |link| [link[:dst_note_id], link[:hier_role]] }
    end
  end
end
