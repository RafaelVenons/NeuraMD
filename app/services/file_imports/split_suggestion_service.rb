# frozen_string_literal: true

module FileImports
  class SplitSuggestionService
    Suggestion = Struct.new(:title, :start_line, :end_line, :line_count, :level, keyword_init: true)

    MIN_SECTION_LINES = 10
    MAX_CHILDREN = 20
    CHILDREN_PER_GROUP = 10
    SUMARIO_PATTERN = /\A(sum[aá]rio|[ií]ndice|table of contents|contents)\z/i

    Section = Struct.new(:title, :level, :start_line, :end_line, :body_line_count, :children, :parent, keyword_init: true)

    def self.call(markdown:, filename: nil, split_level: nil)
      new(markdown, filename, split_level).call
    end

    def initialize(markdown, filename, split_level)
      @markdown = markdown.to_s
      @filename = filename
      @split_level = split_level&.to_i
      @lines = @markdown.lines.map(&:chomp)
    end

    def call
      sections = parse_sections
      return [single_suggestion] if sections.empty?

      effective_level = resolve_split_level(sections)
      sections = apply_split_level(sections, effective_level)

      merge_anemic_sections!(sections)
      recompute_line_ranges!(sections)

      sections.map do |s|
        Suggestion.new(
          title: s.title,
          start_line: s.start_line,
          end_line: s.end_line,
          line_count: s.end_line - s.start_line + 1,
          level: s.level
        )
      end
    end

    private

    def parse_sections
      sections = []
      stack = []

      @lines.each_with_index do |line, idx|
        next unless line.match?(/\A#+\s/)

        level = line[/\A(#+)/, 1].length
        title = line.sub(/\A#+\s*/, "").strip
        section = Section.new(
          title: title, level: level,
          start_line: idx, end_line: nil,
          body_line_count: 0, children: [], parent: nil
        )

        while stack.any? && stack.last.level >= level
          stack.pop
        end

        if stack.any?
          section.parent = stack.last
          stack.last.children << section
        else
          sections << section
        end

        stack << section
      end

      # Compute end_line for each section
      all_flat = flatten(sections)
      all_flat.each_with_index do |sec, i|
        sec.end_line = if i < all_flat.size - 1
          all_flat[i + 1].start_line - 1
        else
          @lines.size - 1
        end
        # body lines = lines between heading and next heading (excluding blank-only)
        body_range = (sec.start_line + 1..sec.end_line)
        sec.body_line_count = body_range.count { |li| @lines[li]&.strip&.present? }
      end

      sections
    end

    def resolve_split_level(sections)
      return nil if @split_level.nil?
      return auto_detect_level(sections) if @split_level == -1
      return nil if @split_level.negative?
      @split_level
    end

    def auto_detect_level(sections)
      all = flatten(sections)
      h1_count = all.count { |s| s.level == 1 }
      h2_count = all.count { |s| s.level == 2 }

      if h1_count == 1 && h2_count > 1
        2
      elsif h1_count > 1
        1
      elsif h1_count == 0 && h2_count > 1
        2
      else
        0
      end
    end

    def apply_split_level(sections, effective_level)
      return sections if effective_level.nil?

      if effective_level.zero?
        return [sections.first].compact
      end

      # Keep only sections at or above effective_level
      flatten(sections).select { |s| s.level <= effective_level }
    end

    def merge_anemic_sections!(sections)
      return if sections.size <= 1

      # Merge from end to start so indexes stay valid
      i = sections.size - 1
      while i > 0
        section = sections[i]
        if section.body_line_count < MIN_SECTION_LINES && section.level > 1
          # Merge into previous sibling
          prev_section = sections[i - 1]
          prev_section.end_line = section.end_line
          prev_section.body_line_count += section.body_line_count
          sections.delete_at(i)
        end
        i -= 1
      end
    end

    def recompute_line_ranges!(sections)
      sections.each_with_index do |sec, i|
        sec.end_line = if i < sections.size - 1
          sections[i + 1].start_line - 1
        else
          @lines.size - 1
        end
      end
    end

    def flatten(sections)
      result = []
      sections.each do |s|
        result << s
        result.concat(flatten(s.children))
      end
      result
    end

    def single_suggestion
      title = if @filename.present?
        File.basename(@filename, File.extname(@filename)).tr("_-", " ").strip
      else
        "Documento importado"
      end

      Suggestion.new(
        title: title,
        start_line: 0,
        end_line: [@lines.size - 1, 0].max,
        line_count: @lines.size,
        level: 1
      )
    end
  end
end
