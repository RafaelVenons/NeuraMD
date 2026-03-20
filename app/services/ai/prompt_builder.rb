require_relative "error"

module Ai
  class PromptBuilder
    GRAMMAR_REVIEW_PROMPT = <<~PROMPT.freeze
      You are a grammar and spelling corrector.
      Fix only grammar, spelling, punctuation, and obvious typos.
      Preserve the original meaning, tone, structure, and Markdown formatting.
      Do not explain your changes.
      Return only the corrected text.
    PROMPT

    SUGGEST_PROMPT = <<~PROMPT.freeze
      You are an editorial assistant.
      Improve clarity, flow, and readability while preserving meaning and Markdown formatting.
      Keep the text concise and natural.
      Do not explain your changes.
      Return only the revised text.
    PROMPT

    REWRITE_PROMPT = <<~PROMPT.freeze
      You are a rewriting assistant.
      Rewrite the text to be clearer and more polished while preserving intent and Markdown formatting.
      Do not add explanations.
      Return only the rewritten text.
    PROMPT

    TRANSLATE_PROMPT = <<~PROMPT.freeze
      You are a translation assistant.
      Translate the text accurately while preserving meaning, structure, formatting, and Markdown.
      Do not explain your choices.
      Return only the translated text.
    PROMPT

    SEED_NOTE_PROMPT = <<~PROMPT.freeze
      You are a note-seeding assistant.
      Draft an initial markdown note that is structurally useful, factually cautious, and easy to expand.
      Use headings and bullets only when they improve the note.
      Preserve the language requested by the user context.
      Do not explain your choices.
      Return only the markdown content.
    PROMPT

    PROMPTS = {
      "grammar_review" => GRAMMAR_REVIEW_PROMPT,
      "suggest" => SUGGEST_PROMPT,
      "rewrite" => REWRITE_PROMPT,
      "translate" => TRANSLATE_PROMPT,
      "seed_note" => SEED_NOTE_PROMPT
    }.freeze

    def self.system_prompt(capability:, language: nil, target_language: nil)
      prompt = PROMPTS.fetch(capability.to_s) do
        raise InvalidCapabilityError, "Capability de IA invalida."
      end

      if capability.to_s == "translate"
        details = []
        details << "Source language: #{language}." if language.present?
        details << "Target language: #{target_language}." if target_language.present?
        return [prompt, details.join("\n")].reject(&:blank?).join("\n\n")
      end

      return prompt if language.blank?
      "#{prompt}\n\nPreferred language of the output: #{language}."
    end
  end
end
