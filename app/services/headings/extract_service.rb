module Headings
  class ExtractService
    Heading = Struct.new(:level, :text, :slug, :position, keyword_init: true)

    HEADING_RE = /\A(\#{1,6})\s+(.+)/
    FENCE_RE = /\A```/

    def self.call(content)
      new(content).call
    end

    def initialize(content)
      @content = content.to_s
    end

    def call
      headings = []
      slug_counts = Hash.new(0)
      in_fence = false

      @content.each_line do |line|
        line = line.chomp

        if line.match?(FENCE_RE)
          in_fence = !in_fence
          next
        end
        next if in_fence

        match = line.match(HEADING_RE)
        next unless match

        level = match[1].length
        raw_text = strip_inline_markdown(match[2].strip)
        slug = generate_slug(raw_text, slug_counts)

        headings << Heading.new(level:, text: raw_text, slug:, position: headings.size)
      end

      headings
    end

    private

    def strip_inline_markdown(text)
      text
        .gsub(/\*\*|__/, "")          # bold markers
        .gsub(/[*_`]/, "")            # italic, inline code markers
        .gsub(/\[([^\]]+)\]\([^)]*\)/, '\1') # [text](url) → text
        .strip
    end

    def generate_slug(text, slug_counts)
      base = ActiveSupport::Inflector.transliterate(text)
        .downcase
        .gsub(/[^\w\s-]/, "")
        .gsub(/[\s_]+/, "-")
        .gsub(/-+/, "-")
        .gsub(/\A-|-\z/, "")

      base = "heading" if base.blank?

      count = slug_counts[base]
      slug_counts[base] += 1
      count.zero? ? base : "#{base}-#{count}"
    end
  end
end
