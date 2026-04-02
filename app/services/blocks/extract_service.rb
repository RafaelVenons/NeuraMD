module Blocks
  class ExtractService
    Block = Struct.new(:block_id, :content, :block_type, :position, keyword_init: true)

    BLOCK_ID_RE = /\s\^([a-zA-Z0-9-]+)\s*$/
    FENCE_RE = /\A```/
    HEADING_RE = /\A\#{1,6}\s/
    LIST_ITEM_RE = /\A\s*(?:[-*]|\d+\.)\s/
    BLOCKQUOTE_RE = /\A>\s/
    MAX_CONTENT_LENGTH = 200

    def self.call(content)
      new(content).call
    end

    def initialize(content)
      @content = content.to_s
    end

    def call
      blocks = []
      in_fence = false

      @content.each_line do |line|
        line = line.chomp

        if line.match?(FENCE_RE)
          in_fence = !in_fence
          next
        end
        next if in_fence

        match = line.match(BLOCK_ID_RE)
        next unless match

        block_id = match[1]
        stripped = line.sub(BLOCK_ID_RE, "").strip
        block_type = detect_type(stripped)

        blocks << Block.new(
          block_id: block_id,
          content: stripped.truncate(MAX_CONTENT_LENGTH, omission: "..."),
          block_type: block_type,
          position: blocks.size
        )
      end

      blocks
    end

    private

    def detect_type(line)
      if line.match?(HEADING_RE)
        "heading"
      elsif line.match?(LIST_ITEM_RE)
        "list_item"
      elsif line.match?(BLOCKQUOTE_RE)
        "blockquote"
      else
        "paragraph"
      end
    end
  end
end
