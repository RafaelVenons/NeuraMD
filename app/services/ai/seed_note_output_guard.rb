require_relative "error"

module Ai
  class SeedNoteOutputGuard
    UUID_RE = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i
    UUID_PAYLOAD_RE = /\A(?:[fcb]:)?#{UUID_RE}\z/i
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
      normalized = OutputSanitizer.normalize(@content)

      raise InvalidOutputError, "A resposta da IA voltou vazia para a nota criada." if normalized.blank?

      validate_no_prompt_echo!(normalized)
      normalized = WikilinkOutputGuard.validate!(content: normalized)

      normalized
    end

    private

    def validate_no_prompt_echo!(text)
      if text == @input_text.strip
        raise InvalidOutputError, "A resposta da IA repetiu o prompt bruto da nota criada."
      end

      return unless FORBIDDEN_PROMPT_MARKERS.any? { |marker| text.include?(marker) }

      raise InvalidOutputError, "A resposta da IA incluiu instrucoes internas do prompt da nota criada."
    end
  end
end
