require_relative "error"

module Ai
  class PromptBuilder
    WIKILINK_PRESERVATION_RULES = <<~RULES.freeze
      If the source text contains wikilinks, preserve the exact payloads in formats like [[Title|uuid]], [[Title|f:uuid]], [[Title|c:uuid]], and [[Title|b:uuid]].
      You may rewrite only the visible text before the pipe.
      Never invent, drop, or rewrite wikilink UUIDs or role prefixes.
    RULES

    GRAMMAR_REVIEW_PROMPT = <<~PROMPT.freeze
      You are a grammar and spelling corrector.
      Fix only grammar, spelling, punctuation, and obvious typos.
      Preserve the original meaning, tone, structure, and Markdown formatting.
      #{WIKILINK_PRESERVATION_RULES.chomp}
      Do not explain your changes.
      Return only the corrected text.
    PROMPT

    REWRITE_PROMPT = <<~PROMPT.freeze
      You are a rewriting assistant.
      Rewrite the text to be clearer and more polished while preserving intent and Markdown formatting.
      #{WIKILINK_PRESERVATION_RULES.chomp}
      Do not add explanations.
      Return only the rewritten text.
    PROMPT

    TRANSLATE_PROMPT = <<~PROMPT.freeze
      You are a translation assistant.
      Translate the text accurately while preserving meaning, structure, formatting, and Markdown.
      #{WIKILINK_PRESERVATION_RULES.chomp}
      Do not explain your choices.
      Return only the translated text.
    PROMPT

    SEED_NOTE_PROMPT = <<~PROMPT.freeze
      You are a note-seeding assistant.
      Draft an initial markdown note that is structurally useful, factually cautious, and easy to expand.
      Use headings and bullets only when they improve the note.
      Preserve the language requested by the user context.
      Never wrap the answer in ```markdown fences or any other code fence.
      Never repeat the prompt, request metadata, or source-note instructions in the output.
      If you keep wikilinks, preserve the exact formats [[Title|uuid]], [[Title|f:uuid]], [[Title|c:uuid]], and [[Title|b:uuid]].
      Never invent, drop, or rewrite wikilink UUIDs.
      Do not explain your choices.
      Return only the markdown content.
    PROMPT

    PROMPTS = {
      "grammar_review" => GRAMMAR_REVIEW_PROMPT,
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
        details << "Return the full answer only in #{target_language}." if target_language.present?
        details << "Do not answer in the source language unless the user explicitly asks for a bilingual result." if target_language.present?
        return [prompt, details.join("\n")].reject(&:blank?).join("\n\n")
      end

      return prompt if language.blank?
      [
        prompt,
        "Preferred language of the output: #{language}.",
        "Return the full answer only in #{language}.",
        "Do not translate the text to another language."
      ].join("\n")
    end
  end
end
