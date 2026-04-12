# frozen_string_literal: true

require "set"

module FileImports
  # Given a list of TOC entries and a markdown body, finds the line in the
  # markdown where each entry's corresponding heading lives. Uses lightweight
  # fuzzy matching (normalized title equality, prefix match, token Jaccard).
  #
  # Does NOT mutate inputs. Returns a new array of hashes with :body_line and
  # :confidence keys added. Entries with no match get :body_line = nil.
  class HeadingMatcher
    JACCARD_MIN = 0.6

    BodyHeading = Struct.new(:line, :level, :text, :normalized, keyword_init: true)

    def self.call(markdown:, entries:, skip_before_line: nil)
      new(markdown, entries, skip_before_line).call
    end

    def initialize(markdown, entries, skip_before_line)
      @markdown = markdown.to_s
      @entries = entries
      @skip_before_line = skip_before_line
    end

    def call
      body_headings = extract_body_headings
      # Only consider headings AFTER the TOC anchor region (if provided)
      if @skip_before_line
        body_headings = body_headings.reject { |h| h.line <= @skip_before_line }
      end

      used = {}
      @entries.map do |entry|
        match = find_match(entry, body_headings, used)
        if match
          used[match.line] = true
          entry_to_hash(entry).merge(body_line: match.line,
                                     confidence: confidence_score(entry, match),
                                     body_level: match.level,
                                     matched_heading: match.text)
        else
          entry_to_hash(entry).merge(body_line: nil, confidence: 0.0,
                                     body_level: nil, matched_heading: nil)
        end
      end
    end

    private

    def entry_to_hash(entry)
      { level: entry.level, number: entry.number, title: entry.title,
        page: entry.page, raw_line: entry.raw_line, source_line: entry.source_line }
    end

    # Extract every heading-like line from the body. We accept:
    #   - # … ###### Markdown headings
    #   - Lines matching patterns like "CHAPTER N Title" even when not #-prefixed
    #     (some pymupdf4llm output has these as plain bold or caps text).
    def extract_body_headings
      out = []
      @markdown.lines.each_with_index do |line, idx|
        stripped = line.chomp.strip
        next if stripped.empty?

        text, level = heading_text_and_level(stripped)
        next unless text

        out << BodyHeading.new(line: idx, level: level, text: text,
                               normalized: normalize(text))
      end
      out
    end

    def heading_text_and_level(stripped)
      if (m = stripped.match(/\A(#+)\s+(.+?)\s*\z/))
        inner = cleanup_heading_text(m[2])
        return nil if inner.empty?
        return [inner, m[1].length]
      end

      if (m = stripped.match(/\A\*\*(.+?)\*\*\s*\z/))
        inner = cleanup_heading_text(m[1])
        return nil if inner.empty?
        return [inner, 2]
      end

      # "CHAPTER N Title" as plain text (Theodoridis/Luger-style after conversion)
      if stripped.match?(/\A(CHAPTER|PART|PARTE|Cap[íi]tulo)\s+[\dIVX]+\b/i) && stripped.length < 200
        inner = cleanup_heading_text(stripped)
        return nil if inner.empty?
        return [inner, 1]
      end

      nil
    end

    # Try exact normalized equality, then tail-equality (drop leading number),
    # then token Jaccard.
    def find_match(entry, body_headings, used)
      target = normalize(entry.title)
      return nil if target.empty?

      number = entry.number

      candidates = body_headings.reject { |h| used[h.line] }

      # Tier 1: exact normalized equality
      exact = candidates.find { |h| h.normalized == target }
      return exact if exact

      # Tier 2: body heading contains target OR target contains body heading
      loose = candidates.find do |h|
        (h.normalized.length >= 4 && target.length >= 4) &&
          (h.normalized.include?(target) || target.include?(h.normalized))
      end
      return loose if loose

      # Tier 3: explicit number prefix (e.g. "2.1 Foo" ↔ body heading "2.1 Foo")
      if number
        with_num = candidates.find { |h| h.text.match?(/\b#{Regexp.escape(number)}\b/) && jaccard(target, h.normalized) >= 0.4 }
        return with_num if with_num
      end

      # Tier 4: token Jaccard ≥ threshold
      best = candidates.map { |h| [h, jaccard(target, h.normalized)] }
                       .select { |(_, s)| s >= JACCARD_MIN }
                       .max_by { |(_, s)| s }
      best ? best.first : nil
    end

    def confidence_score(entry, match)
      t = normalize(entry.title)
      return 1.0 if match.normalized == t
      return 0.9 if match.normalized.include?(t) || t.include?(match.normalized)
      jaccard(t, match.normalized)
    end

    def jaccard(a, b)
      ta = a.split(/\s+/).to_set
      tb = b.split(/\s+/).to_set
      return 0.0 if ta.empty? || tb.empty?
      inter = (ta & tb).size
      union = (ta | tb).size
      inter.to_f / union
    end

    def normalize(text)
      s = cleanup_heading_text(text).downcase
      s = s.tr("áàâãäéèêëíìîïóòôõöúùûüç", "aaaaaeeeeiiiiooooouuuuc")
      s = s.gsub(/\s+\.{2,}\s*\d+\s*\z/, "")
      s = s.gsub(/\s+\d{1,4}\s*\z/, "")
      s = s.gsub(/\A(\d+(?:\.\d+)*|chapter\s+\d+|cap[íi]tulo\s+\d+|part[ei]?\s+[ivx\d]+|appendix\s+\w+)[\s.:\-—]+/i, "")
      s = s.gsub(/[^\p{L}\p{N}\s]/, " ")
      s.split.join(" ")
    end

    def cleanup_heading_text(text)
      s = text.to_s.strip
      if s.include?("|")
        columns = s.split("|").map(&:strip).reject(&:empty?)
        s = columns.join(" ") unless columns.empty?
      end
      s = s.gsub(/\*\*/, "")
      s = s.gsub(/\A\|+/, "").gsub(/\|+\z/, "")
      s = s.gsub(/\.{2,}\s*\d+\s*\z/, "")
      s.split.join(" ")
    end
  end
end
