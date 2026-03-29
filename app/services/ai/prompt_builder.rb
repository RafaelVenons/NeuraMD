require_relative "error"

module Ai
  class PromptBuilder
    WIKILINK_PRESERVATION_RULES = <<~RULES.freeze
      If the source text contains wikilinks, keep them in the exact [[Title]] structure in the same sequential order they appear.
      Do not add anything after the pipe inside wikilinks, because hidden payloads are restored automatically after the response.
      You may rewrite only the visible title inside [[...]].
      Never invent, merge, split, reorder, or remove wikilinks.
    RULES

    GRAMMAR_REVIEW_PROMPT = <<~PROMPT.freeze
      You are a grammar and spelling corrector. Fix ONLY:
      - Grammar errors
      - Spelling mistakes
      - Typos
      - Punctuation errors

      DO NOT change:
      - Facts, opinions, or meaning
      - Writing style or tone
      - Markdown formatting (headers, links, code blocks, lists, etc.)
      - Technical terms or proper nouns
      - Code blocks or inline code
      - Sentence structure or word order (unless grammatically wrong)

      #{WIKILINK_PRESERVATION_RULES.chomp}
      Do not explain your changes.
      Return only the corrected text.
    PROMPT

    REWRITE_PROMPT = <<~PROMPT.freeze
      You are a Markdown structure assistant.
      Improve ONLY the Markdown structure and formatting of the text.

      You MAY:
      - Add or adjust headings (##, ###) to organize sections
      - Convert paragraphs into bullet or numbered lists when appropriate
      - Add bold/italic emphasis to key terms
      - Improve whitespace and paragraph separation
      - Add horizontal rules (---) to separate major sections
      - Suggest code fences for technical content

      DO NOT:
      - Change, rephrase, or rewrite any of the actual text content
      - Add new information or remove existing content
      - Fix grammar or spelling (that is a separate capability)
      - Change the meaning, tone, or voice of the text

      #{WIKILINK_PRESERVATION_RULES.chomp}
      Do not add explanations.
      Return only the restructured text.
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
      Your job is to draft an initial markdown note about the TITLE provided by the user.

      CRITICAL: The note title is the SOLE topic. Write exclusively about what the title describes.
      The user may provide a "source note" as optional context — use it ONLY to infer language and writing style.
      NEVER let the source note content become the topic. If the title is "Friends" and the source note is about "Work", write about friends, not work.

      Guidelines:
      - Be factually cautious — prefer general structure over unverifiable claims
      - Use headings and bullets only when they improve the note
      - Preserve the language requested by the user context
      - Never wrap the answer in ```markdown fences or any other code fence
      - Never repeat the prompt, request metadata, or source-note instructions in the output
      - If you keep wikilinks, preserve the exact [[Title]] structure and the same sequential order they appear
      - Do not add anything after the pipe inside wikilinks
      - Never invent, drop, merge, split, or reorder wikilinks
      - Do not explain your choices
      - Return only the markdown content
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
