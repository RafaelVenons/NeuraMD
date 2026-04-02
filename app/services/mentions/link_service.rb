module Mentions
  # Converts the first plain-text mention of a term in a source note into a wikilink.
  # Creates a checkpoint revision on the source note, which triggers link sync.
  class LinkService
    WIKILINK_RE = /\[\[[^\]]*\]\]/
    Result = Struct.new(:revision, :graph_changed, keyword_init: true)

    def self.call(source_note:, target_note:, matched_term:, author:)
      new(source_note:, target_note:, matched_term:, author:).call
    end

    def initialize(source_note:, target_note:, matched_term:, author:)
      @source_note = source_note
      @target_note = target_note
      @matched_term = matched_term
      @author = author
    end

    def call
      content = @source_note.head_revision&.content_markdown.to_s
      new_content = replace_first_plain_mention(content)

      checkpoint = Notes::CheckpointService.call(
        note: @source_note,
        content: new_content,
        author: @author
      )

      Result.new(revision: checkpoint.revision, graph_changed: checkpoint.graph_changed)
    end

    private

    def replace_first_plain_mention(content)
      # Build a map of wikilink positions to protect
      protected_ranges = []
      content.scan(WIKILINK_RE) do
        m = Regexp.last_match
        protected_ranges << (m.begin(0)...m.end(0))
      end

      # Find the first unprotected occurrence of the matched term
      re = /#{Regexp.escape(@matched_term)}/i
      content.match(re) do |_|
        # Scan all matches to find first outside wikilinks
      end

      result = content.dup
      offset = 0
      replacement = "[[#{@matched_term}|#{@target_note.id}]]"

      content.enum_for(:scan, re).each do
        m = Regexp.last_match
        pos = m.begin(0)
        next if protected_ranges.any? { |r| r.cover?(pos) }

        result[pos + offset, m[0].length] = replacement
        break # only replace first
      end

      result
    end
  end
end
