module Ai
  class WikilinkOutputGuard
    UUID_RE = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i
    UUID_PAYLOAD_RE = /\A(?:[fcb]:)?#{UUID_RE}(?:#[a-z0-9_-]+|\^[a-zA-Z0-9-]+)?\z/i
    WIKILINK_RE = /!?\[\[(?<body>[^\]]+)\]\]/.freeze

    def self.normalize!(content:, source_text: nil)
      new(content:, source_text:).normalize!
    end

    def self.validate!(content:, source_text: nil)
      normalize!(content:, source_text:)
    end

    def initialize(content:, source_text:)
      @content = content.to_s
      @source_text = source_text.to_s
    end

    def normalize!
      normalized = OutputSanitizer.normalize(@content)
      normalized = restore_missing_payloads(normalized)
      normalized = sanitize_wikilinks(normalized)
      @content = normalized
      normalized = preserve_missing_payloads(@content) if @source_text.present?
      @content = normalized
      normalized
    end

    private

    LinkToken = Struct.new(:full_match, :display, :payload, :start_pos, :end_pos, :line_index, keyword_init: true)

    def preserve_missing_payloads(text)
      source_payloads = extract_payloads(@source_text)
      return text if source_payloads.empty?

      output_payloads = extract_payloads(text)
      missing_payloads = source_payloads - output_payloads
      return text if missing_payloads.empty?

      missing_links = extract_links(@source_text).select do |link|
        link.payload.present? && missing_payloads.include?(normalized_payload(link.payload))
      end
      append_missing_links_to_last_line(text, missing_links)
    end

    def sanitize_wikilinks(text)
      opening = text.scan(/\[\[/).length
      closing = text.scan(/\]\]/).length
      return text if opening != closing

      text.gsub(WIKILINK_RE) do |_match|
        body = Regexp.last_match[:body].to_s
        display, payload = body.split("|", 2)
        next Regexp.last_match[0] if payload.blank?
        next Regexp.last_match[0] if display.to_s.strip.present? && payload.to_s.strip.match?(UUID_PAYLOAD_RE)

        "[[#{display.to_s.strip}]]"
      end
    end

    def extract_payloads(text)
      text.scan(WIKILINK_RE).flatten.each_with_object([]) do |body, payloads|
        _, payload = body.split("|", 2)
        next if payload.blank?
        next unless payload.to_s.strip.match?(UUID_PAYLOAD_RE)

        payloads << payload.to_s.strip.downcase
      end.uniq
    end

    def restore_missing_payloads(text)
      source_links = extract_links(@source_text).select { |link| link.payload.present? }
      return text if source_links.empty?

      normalized = String(text)
      output_links = extract_links(normalized)
      output_payloads = output_links.filter_map { |link| normalized_payload(link.payload) }.uniq
      missing_links = source_links.reject { |link| output_payloads.include?(normalized_payload(link.payload)) }
      return normalized if missing_links.empty?

      bare_links = output_links.select { |link| link.payload.blank? }
      replacements = {}

      missing_links.zip(bare_links).each do |source_link, bare_link|
        break if source_link.nil? || bare_link.nil?
        replacements[bare_link.object_id] = source_link.payload
      end

      normalized = apply_payload_replacements(normalized, bare_links, replacements)
      restore_payloads_from_plain_text(normalized, source_links)
    end

    def apply_payload_replacements(text, bare_links, replacements)
      return text if replacements.empty?

      bare_links
        .select { |link| replacements.key?(link.object_id) }
        .sort_by(&:start_pos)
        .reverse_each
        .reduce(String(text)) do |buffer, link|
          payload = replacements.fetch(link.object_id)
          replacement = "[[#{link.display}|#{payload}]]"
          buffer[link.start_pos...link.end_pos] = replacement
          buffer
        end
    end

    def extract_links(text)
      text.to_s.to_enum(:scan, WIKILINK_RE).map do
        match = Regexp.last_match
        body = match[:body].to_s
        display, payload = body.split("|", 2)
        LinkToken.new(
          full_match: match[0],
          display: display.to_s.strip,
          payload: payload.to_s.strip.presence,
          start_pos: match.begin(0),
          end_pos: match.end(0),
          line_index: line_index_for(text, match.begin(0))
        )
      end
    end

    def normalized_payload(payload)
      payload.to_s.strip.downcase.presence
    end

    def normalized_display(display)
      display.to_s.strip.downcase.gsub(/\s+/, " ")
    end

    def append_missing_links_to_last_line(text, missing_links)
      return text if missing_links.empty?

      normalized = String(text)
      return missing_links.map { |link| "[[#{link.display}|#{link.payload}]]" }.uniq.join(" ") if normalized.blank?

      lines = normalized.split("\n", -1)
      grouped_additions = missing_links.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |link, hash|
        addition = "[[#{link.display}|#{link.payload}]]"
        hash[link.line_index] << addition unless hash[link.line_index].include?(addition)
      end

      grouped_additions.each do |source_line_index, additions|
        target_index = [source_line_index, lines.length - 1].min
        suffix = additions.join(" ")
        lines[target_index] =
          if lines[target_index].blank?
            suffix
          else
            "#{lines[target_index]} #{suffix}"
          end
      end

      lines.join("\n")
    end

    def restore_payloads_from_plain_text(text, source_links)
      normalized = String(text)
      output_payloads = extract_links(normalized).filter_map { |link| normalized_payload(link.payload) }.uniq
      missing_links = source_links.reject { |link| output_payloads.include?(normalized_payload(link.payload)) }
      return normalized if missing_links.empty?

      missing_links.each do |source_link|
        range = plain_text_match_range(normalized, source_link.display)
        next unless range

        replacement = "[[#{normalized[range]}|#{source_link.payload}]]"
        normalized[range] = replacement
      end

      normalized
    end

    def plain_text_match_range(text, display)
      needle = display.to_s
      return if needle.blank?

      link_ranges = extract_links(text).map { |link| link.start_pos...link.end_pos }
      offset = 0

      while (index = text.index(needle, offset))
        range = index...(index + needle.length)
        return range unless link_ranges.any? { |link_range| overlap?(link_range, range) }

        offset = index + needle.length
      end

      nil
    end

    def overlap?(left, right)
      left.begin < right.end && right.begin < left.end
    end

    def line_index_for(text, offset)
      text.to_s.slice(0, offset).to_s.count("\n")
    end
  end
end
