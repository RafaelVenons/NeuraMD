module Mentions
  # Finds notes whose content mentions the given note's title or aliases
  # as plain text (not inside a wikilink). Returns source notes with context snippets.
  class UnlinkedService
    Mention = Struct.new(:source_note, :matched_term, :snippets, keyword_init: true)
    Result = Struct.new(:mentions, keyword_init: true)

    WIKILINK_RE = /\[\[[^\]]*\]\]/
    FENCED_CODE_RE = /```.*?```/m
    INLINE_CODE_RE = /`[^`]+`/
    MIN_TERM_LENGTH = 3
    SNIPPET_RADIUS = 40

    def self.call(note:)
      new(note: note).call
    end

    def initialize(note:)
      @note = note
    end

    def call
      terms = collect_terms
      return Result.new(mentions: []) if terms.empty?

      linked_ids = NoteLink.where(dst_note_id: @note.id, active: true).pluck(:src_note_id)
      excluded_ids = linked_ids + [@note.id]
      @dismissed = MentionExclusion.where(note_id: @note.id).pluck(:source_note_id, :matched_term).to_set

      candidates = sql_candidates(terms, excluded_ids)
      mentions = extract_mentions(candidates, terms)
      Result.new(mentions: mentions)
    end

    private

    def collect_terms
      terms = [@note.title]
      terms += @note.note_aliases.pluck(:name)
      terms.reject(&:blank?).select { |t| t.length >= MIN_TERM_LENGTH }.uniq
    end

    def sql_candidates(terms, excluded_ids)
      conditions = terms.map do |term|
        sanitized = ActiveRecord::Base.connection.quote_string(term)
        "note_revisions.content_plain ILIKE '%#{sanitized}%'"
      end

      Note.active
        .joins("INNER JOIN note_revisions ON note_revisions.id = notes.head_revision_id")
        .where.not(id: excluded_ids)
        .where(conditions.join(" OR "))
        .includes(:head_revision)
        .to_a
    end

    def extract_mentions(candidates, terms)
      seen_ids = Set.new
      mentions = []

      candidates.each do |note|
        markdown = note.head_revision&.content_markdown.to_s
        stripped = markdown
          .gsub(FENCED_CODE_RE, "\0" * 10)
          .gsub(INLINE_CODE_RE, "\0" * 10)
          .gsub(WIKILINK_RE, "\0" * 10)

        matched_terms_snippets = []

        terms.each do |term|
          next if @dismissed.include?([note.id, term])

          re = /#{Regexp.escape(term)}/i
          next unless stripped.match?(re)

          snippets = extract_snippets(stripped, markdown, re, term)
          matched_terms_snippets << {term: term, snippets: snippets} if snippets.any?
        end

        next if matched_terms_snippets.empty?
        next if seen_ids.include?(note.id)
        seen_ids.add(note.id)

        best = matched_terms_snippets.first
        mentions << Mention.new(
          source_note: note,
          matched_term: best[:term],
          snippets: best[:snippets]
        )
      end

      mentions
    end

    def extract_snippets(stripped, markdown, re, term)
      snippets = []
      stripped.scan(re) do
        match = Regexp.last_match
        pos = match.begin(0)
        start = [pos - SNIPPET_RADIUS, 0].max
        finish = [pos + term.length + SNIPPET_RADIUS, markdown.length].min
        raw = markdown[start...finish]
        # Sanitize HTML and highlight
        safe = ERB::Util.html_escape(raw)
        highlighted = safe.gsub(/#{Regexp.escape(ERB::Util.html_escape(term))}/i) do |m|
          "<mark>#{m}</mark>"
        end
        prefix = start > 0 ? "..." : ""
        suffix = finish < markdown.length ? "..." : ""
        snippets << "#{prefix}#{highlighted}#{suffix}"
      end
      snippets.first(2) # limit snippets per mention
    end
  end
end
