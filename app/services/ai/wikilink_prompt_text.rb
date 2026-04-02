module Ai
  class WikilinkPromptText
    UUID_RE = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i
    PAYLOAD_RE = /(?:[fcb]:)?#{UUID_RE}(?:#[a-z0-9_-]+|\^[a-zA-Z0-9-]+)?/i
    WIKILINK_WITH_PAYLOAD_RE = /(?<prefix>!?)\[\[(?<display>[^\]|]+?)\|(?<payload>#{PAYLOAD_RE})\]\]/i

    def self.normalize(text)
      text.to_s.gsub(WIKILINK_WITH_PAYLOAD_RE) do
        "#{Regexp.last_match[:prefix]}[[#{Regexp.last_match[:display].to_s.strip}]]"
      end
    end
  end
end
