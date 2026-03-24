module Ai
  class OutputSanitizer
    OUTER_MARKDOWN_FENCE_RE = /\A```(?:markdown|md)?[ \t]*\r?\n(?<body>[\s\S]*?)\r?\n```\s*\z/i

    def self.normalize(content)
      new(content).normalize
    end

    def initialize(content)
      @content = content.to_s
    end

    def normalize
      normalized = strip_bom(@content).strip
      unwrap_outer_markdown_fence(normalized)
    end

    private

    def strip_bom(text)
      text.sub(/\A\uFEFF/, "")
    end

    def unwrap_outer_markdown_fence(text)
      match = text.match(OUTER_MARKDOWN_FENCE_RE)
      return text unless match

      match[:body].to_s.strip
    end
  end
end
