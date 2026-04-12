# frozen_string_literal: true

module FileImports
  # Detects a Table of Contents in a markdown document and parses its entries
  # into a flat, ordered list with hierarchical level. Ruby-only, no I/O, no AR.
  #
  # Output shape:
  #   {
  #     anchor_line: Integer,          # 0-based line index of the TOC heading
  #     anchor_kind: String,           # "Contents" | "Sumário" | …
  #     entries: [
  #       { level: 0..4, number: "2.1" | nil, title: String,
  #         page: Integer | nil, raw_line: String, source_line: Integer }
  #     ]
  #   }
  #
  # Returns nil if no TOC anchor is found or fewer than 2 entries are parseable.
  class TocDetector
    ANCHOR_NAMES = %w[
      Sumário Sumario Índice Indice Contents
    ].freeze
    ANCHOR_PHRASES = ["Table of Contents", "Brief Contents"].freeze
    BLOCKLIST_TITLES = [
      "preface",
      "prefacio",
      "capa",
      "folha de rosto",
      "creditos",
      "cover",
      "title page",
      "epigraph",
      "index",
      "bibliography",
      "references",
      "acknowledgements",
      "brief contents",
      "publisher s acknowledgements"
    ].freeze

    MAX_SCAN_LINES = 400          # stop scanning after this many lines past anchor
    MIN_ENTRIES_TO_COMMIT = 3

    Entry = Struct.new(:level, :number, :title, :page, :raw_line, :source_line,
                       keyword_init: true)

    def self.call(markdown:)
      new(markdown).call
    end

    def initialize(markdown)
      @lines = markdown.to_s.lines.map(&:chomp)
    end

    def call
      anchor = find_anchor
      return nil unless anchor

      entries = parse_entries_from(anchor[:line])
      return nil if entries.size < MIN_ENTRIES_TO_COMMIT

      {
        anchor_line: anchor[:line],
        anchor_kind: anchor[:kind],
        entries: entries
      }
    end

    private

    # ── Anchor detection ────────────────────────────────────────────────────

    # Find the best anchor line. Prefers "Contents" over "Brief Contents" when
    # both are present. Accepts three syntaxes:
    #   - markdown heading: "## Contents"
    #   - bold-only line:   "**Sumário**"
    #   - plain line alone: "Contents" (uppercase or title-case, flanked by blanks)
    def find_anchor
      candidates = []

      @lines.each_with_index do |line, idx|
        kind = anchor_kind_for(line, idx)
        next unless kind
        candidates << { line: idx, kind: kind, priority: anchor_priority(kind) }
      end

      return nil if candidates.empty?
      candidates.min_by { |c| [-c[:priority], c[:line]] }
    end

    def anchor_kind_for(line, idx)
      stripped = line.strip
      return nil if stripped.empty?

      # Heading syntax
      if (m = stripped.match(/\A#{'#'}+\s+(.+?)\s*\z/))
        inner = unwrap_wrappers(m[1])
        return inner if anchor_name?(inner)
      end

      # Bold-only line
      if (m = stripped.match(/\A\*\*(.+?)\*\*\z/))
        return m[1].strip if anchor_name?(m[1].strip)
      end

      # Plain line flanked by blanks (slides often render this way)
      return nil unless anchor_name?(stripped)
      prev_blank = idx.zero? || @lines[idx - 1].strip.empty?
      next_blank = @lines[idx + 1].nil? || @lines[idx + 1].strip.empty?
      prev_blank && next_blank ? stripped : nil
    end

    def anchor_name?(text)
      normalized = text.gsub(/[*_]/, "").strip
      ANCHOR_NAMES.any? { |n| normalized.casecmp?(n) } ||
        ANCHOR_PHRASES.any? { |p| normalized.casecmp?(p) }
    end

    # "Contents" beats "Brief Contents" (more detailed); markdown heading
    # syntax beats bold-only; explicit anchors beat ambiguous plain text.
    def anchor_priority(kind)
      return 3 if kind.casecmp?("Contents") || kind.casecmp?("Sumário") || kind.casecmp?("Sumario") ||
                  kind.casecmp?("Índice") || kind.casecmp?("Indice") || kind.casecmp?("Table of Contents")
      return 1 if kind.casecmp?("Brief Contents")
      2
    end

    # ── Entry parsing ───────────────────────────────────────────────────────

    def parse_entries_from(anchor_line)
      entries = []
      seen_titles = []
      end_line = [anchor_line + MAX_SCAN_LINES, @lines.size - 1].min

      (anchor_line + 1..end_line).each do |idx|
        line = @lines[idx]
        stripped = line.strip

        # Skip blank lines and horizontal rules
        next if stripped.empty? || stripped.match?(/\A[-=_*]{3,}\z/) || stripped.match?(/\A\|(?:\s*:?-+:?\s*\|)+\s*\z/)

        entry = parse_entry_line(line, idx)
        if entry
          entries << entry
          seen_titles << entry.title
          next
        end

        # Detect end-of-TOC:
        #  (a) a markdown heading (# / ##) after we already parsed ≥ 2 entries
        #      — body almost always uses explicit headings while TOC entries
        #      are plain text;
        #  (b) a heading whose text fuzzy-matches any seen TOC title.
        if markdown_heading?(stripped) && entries.size >= MIN_ENTRIES_TO_COMMIT
          break
        end
        if heading_like?(stripped)
          heading_text = strip_heading_syntax(stripped)
          if heading_text && seen_titles.any? { |t| titles_loose_match?(heading_text, t) }
            break
          end
        end
      end

      entries
    end

    def markdown_heading?(stripped)
      stripped.start_with?("#")
    end

    def heading_like?(stripped)
      stripped.start_with?("#") ||
        stripped.match?(/\A\*\*[^*]+\*\*\z/)
    end

    def strip_heading_syntax(stripped)
      if (m = stripped.match(/\A#+\s+(.+?)\s*\z/))
        inner = unwrap_wrappers(m[1])
        return inner
      end
      if (m = stripped.match(/\A\*\*(.+?)\*\*\z/))
        return m[1].strip
      end
      nil
    end

    # Parses a single TOC entry line. Returns an Entry or nil if unparseable.
    def parse_entry_line(raw_line, source_line)
      line = raw_line.rstrip

      # Capture indentation depth (helps with slide-TOCs that indent subitems)
      indent = line[/\A[ \t]*/].length

      text = strip_heading_syntax(line.strip) || line.strip
      text = normalize_entry_text(text)
      return nil if text.empty?

      # Extract trailing page number (possibly preceded by dotted leaders)
      page = nil
      if (m = text.match(/\s+\.{2,}\s*(\d{1,4})\s*\z/))
        page = m[1].to_i
        text = text[0...m.begin(0)].strip
      elsif (m = text.match(/\s+(\d{1,4})\s*\z/)) && text.length - m[1].length > 6
        # Trailing plain page number (only accept when title part is ≥ 6 chars
        # to avoid mis-interpreting short numeric headings).
        page = m[1].to_i
        text = text[0...m.begin(0)].strip
      end

      text = normalize_entry_text(text)
      return nil if text.empty? || blocklisted_title?(text)

      # Match structured prefixes
      if (m = text.match(/\A(PARTE|PART)\s+([IVXLCivxlc\d]+)(?:\s*[:\-—]\s*|\s+)(.*)\z/))
        title = m[3].strip
        title = m[2] if title.empty?
        return Entry.new(level: 0, number: m[2], title: title,
                         page: page, raw_line: raw_line, source_line: source_line)
      end

      if (m = text.match(/\A(CHAPTER|Chapter|Cap[íi]tulo|CAP[ÍI]TULO)\s+(\d+)(?:\s*[:\-—\.]\s*|\s+)(.+)\z/))
        return Entry.new(level: 1, number: m[2], title: m[3].strip,
                         page: page, raw_line: raw_line, source_line: source_line)
      end

      if (m = text.match(/\A(\d+)\.?\s+(.+)\z/))
        title = m[2].strip
        return nil if title.empty? || blocklisted_title?(title)

        return Entry.new(level: 1, number: m[1], title: title,
                         page: page, raw_line: raw_line, source_line: source_line)
      end

      # Numeric N.N.N.N prefix
      if (m = text.match(/\A(\d+(?:\.\d+){0,3})\.?\s+(.+)\z/))
        number = m[1]
        depth = number.count(".") + 1
        # "1.0 Introduction" and "1.1" count as sub-sections
        level = depth # 1 = chapter, 2 = section, 3+ = subsection
        return Entry.new(level: level, number: number, title: m[2].strip,
                         page: page, raw_line: raw_line, source_line: source_line)
      end

      # Appendix
      if (m = text.match(/\AAPPENDIX\s+([A-Z])(?:\s*[:\-—\.]\s*|\s+)(.+)\z/i))
        return Entry.new(level: 1, number: "App#{m[1].upcase}", title: m[2].strip,
                         page: page, raw_line: raw_line, source_line: source_line)
      end

      # Bulleted (slide TOCs)
      if (m = text.match(/\A[•·\-*]\s+(.+)\z/))
        return Entry.new(level: 1, number: nil, title: m[1].strip,
                         page: page, raw_line: raw_line, source_line: source_line)
      end

      # Bare title line — accept only if it looks title-cased and has ≥ 3 words
      # or is all-caps of ≥ 2 words (common for PARTE headings in slides).
      if plausible_bare_title?(text)
        # Heuristic level: indent-driven (each 2 spaces = deeper level,
        # capped at 3). Level 1 if indent ≤ 2.
        level = [indent / 2, 0].max.clamp(1, 3)
        level = 0 if text.match?(/\A(PARTE|PART)\s+[IVXLC\d]+\z/i)
        return Entry.new(level: level, number: nil, title: text,
                         page: page, raw_line: raw_line, source_line: source_line)
      end

      nil
    end

    def plausible_bare_title?(text)
      return false if text.length < 3 || text.length > 150
      return false if text.match?(/\A[\d\s\-_.]+\z/)
      words = text.split(/\s+/)
      return false if words.size < 2
      # Accept if either Title Case or ALL CAPS
      all_caps = text == text.upcase && text.match?(/[A-Z]/)
      title_case = words.count { |w| w.match?(/\A[A-ZÁÉÍÓÚÂÊÔÇÃÕ]/) } >= words.size / 2.0
      all_caps || title_case
    end

    # ── Title equivalence (lightweight) ─────────────────────────────────────

    def titles_match?(a, b)
      normalize_title(a) == normalize_title(b)
    end

    # Loose: accept exact OR bi-directional substring (body headings often add
    # a subtitle after the TOC title: "Roadmap da Evolução da IA" vs
    # "Roadmap da Evolução da IA Do Cálculo à Autonomia").
    def titles_loose_match?(a, b)
      na = normalize_title(a)
      nb = normalize_title(b)
      return true if na == nb
      return false if na.length < 4 || nb.length < 4
      na.include?(nb) || nb.include?(na)
    end

    def normalize_title(text)
      s = normalize_entry_text(text).downcase
      s = s.tr("áàâãäéèêëíìîïóòôõöúùûüç", "aaaaaeeeeiiiiooooouuuuc")
      s = s.gsub(/\s+\.{2,}\s*\d+\s*\z/, "") # dotted leader tail
      s = s.gsub(/\s+\d{1,4}\s*\z/, "")       # trailing page number
      s = s.gsub(/\A(\d+(?:\.\d+)*|chapter\s+\d+|cap[íi]tulo\s+\d+|part[ei]?\s+[ivx\d]+)[\s.:\-—]+/i, "")
      s = s.gsub(/[^\p{L}\p{N}\s]/, " ")
      s.split.join(" ")
    end

    def normalize_entry_text(text)
      normalized = text.to_s.strip
      normalized = unwrap_wrappers(normalized)
      normalized = unwrap_pipe_columns(normalized)
      normalized = normalized.gsub(/\*\*/, "")
      normalized = normalized.gsub(/\A\|+/, "").gsub(/\|+\z/, "")
      normalized = normalized.gsub(/\.{2,}\s*\d+\s*\z/, "")
      normalized.split.join(" ")
    end

    def unwrap_wrappers(text)
      text.to_s.sub(/\A\*\*(.+?)\*\*\z/, '\1').strip
    end

    def unwrap_pipe_columns(text)
      return text unless text.include?("|")

      columns = text.split("|").map(&:strip).reject(&:empty?)
      return text if columns.empty? || columns.all? { |col| col.match?(/\A:?-+:?\z/) }

      columns.join(" ")
    end

    def blocklisted_title?(text)
      normalized = normalize_title(text)
      return true if normalized.empty?

      BLOCKLIST_TITLES.any? do |blocked|
        normalized == blocked || normalized.include?(blocked)
      end
    end
  end
end
