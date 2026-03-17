module Links
  # Parses unresolved wiki-link promises from markdown content.
  #
  # Supported format:
  #   [[Future Note Title]]
  #
  # Returns unique array of normalized promise titles.
  class PromiseExtractService
    WIKILINK_PROMISE_RE = /\[\[(?<title>[^\]\|]+)\]\]/

    def self.call(content)
      new(content).call
    end

    def initialize(content)
      @content = content.to_s
    end

    def call
      @content
        .scan(WIKILINK_PROMISE_RE)
        .flatten
        .map { |title| normalize_title(title) }
        .reject(&:blank?)
        .uniq { |title| title.downcase }
    end

    private

    def normalize_title(title)
      title.to_s.squish
    end
  end
end
