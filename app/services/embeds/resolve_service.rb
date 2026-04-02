# frozen_string_literal: true

module Embeds
  class ResolveService
    Result = Struct.new(:content, :found, keyword_init: true)

    HEADING_RE = /\A(\#{1,6})\s+(.+)/
    FENCE_RE = /\A```/
    BLOCK_ID_RE = /\s\^([a-zA-Z0-9-]+)\s*$/

    def self.call(content:, heading_slug: nil, block_id: nil)
      new(content:, heading_slug:, block_id:).call
    end

    def initialize(content:, heading_slug:, block_id:)
      @content = content.to_s
      @heading_slug = heading_slug
      @block_id = block_id
    end

    def call
      return not_found if @content.blank?
      return not_found if @heading_slug.blank? && @block_id.blank?

      if @heading_slug.present?
        resolve_heading
      else
        resolve_block
      end
    end

    private

    def resolve_heading
      lines = @content.lines.map(&:chomp)
      in_fence = false
      slug_counts = Hash.new(0)
      target_line = nil
      target_level = nil

      lines.each_with_index do |line, idx|
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

        if slug == @heading_slug && target_line.nil?
          target_line = idx
          target_level = level
        end
      end

      return not_found unless target_line

      # Find end: next heading with level <= target_level (outside fences)
      end_line = nil
      in_fence = false

      lines.each_with_index do |line, idx|
        next if idx <= target_line

        if line.match?(FENCE_RE)
          in_fence = !in_fence
          next
        end
        next if in_fence

        match = line.match(HEADING_RE)
        if match && match[1].length <= target_level
          end_line = idx
          break
        end
      end

      section = if end_line
        lines[target_line...end_line]
      else
        lines[target_line..]
      end

      # Strip trailing blank lines
      section.pop while section.last&.strip&.empty?

      Result.new(content: section.join("\n"), found: true)
    end

    def resolve_block
      lines = @content.lines.map(&:chomp)
      in_fence = false
      target_idx = nil

      lines.each_with_index do |line, idx|
        if line.match?(FENCE_RE)
          in_fence = !in_fence
          next
        end
        next if in_fence

        match = line.match(BLOCK_ID_RE)
        if match && match[1] == @block_id
          target_idx = idx
          break
        end
      end

      return not_found unless target_idx

      target_line = lines[target_idx]
      stripped = target_line.sub(BLOCK_ID_RE, "").strip

      # For blockquotes, collect contiguous > lines ending at target
      if stripped.start_with?("> ")
        block_lines = collect_blockquote(lines, target_idx)
        Result.new(content: block_lines.join("\n"), found: true)
      else
        Result.new(content: stripped, found: true)
      end
    end

    def collect_blockquote(lines, end_idx)
      start_idx = end_idx
      while start_idx > 0 && lines[start_idx - 1].match?(/\A>\s?/)
        start_idx -= 1
      end

      lines[start_idx..end_idx].map do |line|
        line.sub(BLOCK_ID_RE, "")
      end
    end

    def strip_inline_markdown(text)
      text
        .gsub(/\*\*|__/, "")
        .gsub(/[*_`]/, "")
        .gsub(/\[([^\]]+)\]\([^)]*\)/, '\1')
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

    def not_found
      Result.new(content: nil, found: false)
    end
  end
end
