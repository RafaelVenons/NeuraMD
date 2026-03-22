module Ai
  class SeedNoteOutputGuard
    UUID_RE = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i
    UUID_PAYLOAD_RE = /\A(?:[fcb]:)?#{UUID_RE}\z/i
    OUTER_MARKDOWN_FENCE_RE = /\A```(?:markdown|md)?[ \t]*\r?\n(?<body>[\s\S]*?)\r?\n```\s*\z/i
    FORBIDDEN_PROMPT_MARKERS = [
      "Create an initial markdown note for the new title below.",
      "The title is the primary source of truth for what this new note should cover.",
      "Return only the markdown body.",
      "New note title:",
      "Current note title:",
      "Current note language:",
      "Current note content (optional context):"
    ].freeze

    def self.normalize!(content:, input_text:)
      new(content:, input_text:).normalize!
    end

    def initialize(content:, input_text:)
      @content = content.to_s
      @input_text = input_text.to_s
    end

    def normalize!
      normalized = strip_bom(@content).strip
      normalized = unwrap_outer_markdown_fence(normalized)

      raise InvalidOutputError, "A resposta da IA voltou vazia para a nota criada." if normalized.blank?

      validate_no_prompt_echo!(normalized)
      validate_wikilinks!(normalized)

      normalized
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

    def validate_no_prompt_echo!(text)
      if text == @input_text.strip
        raise InvalidOutputError, "A resposta da IA repetiu o prompt bruto da nota criada."
      end

      return unless FORBIDDEN_PROMPT_MARKERS.any? { |marker| text.include?(marker) }

      raise InvalidOutputError, "A resposta da IA incluiu instrucoes internas do prompt da nota criada."
    end

    def validate_wikilinks!(text)
      opening = text.scan(/\[\[/).length
      closing = text.scan(/\]\]/).length

      if opening != closing
        raise InvalidOutputError, "A resposta da IA quebrou a estrutura de wikilink com colchetes desbalanceados."
      end

      text.scan(/\[\[(?<body>[^\]]+)\]\]/).flatten.each do |body|
        display, payload = body.split("|", 2)
        next if payload.blank?

        if display.to_s.strip.blank? || payload.to_s.strip !~ UUID_PAYLOAD_RE
          raise InvalidOutputError, "A resposta da IA gerou wikilink invalido para a nota criada."
        end
      end
    end
  end
end
