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

    IMPORT_ANALYZE_PROMPT = <<~PROMPT.freeze
      You are a document structure analyst.
      You receive a markdown document converted from a PDF, DOCX, EPUB, or PPTX file.
      Your task: suggest logical split points to divide this into study notes.

      Rules:
      1. If there is a Table of Contents, Summary, or "Sumario", use it as the PRIMARY guide for segmentation.
         The TOC defines the logical chapters — each TOC entry should map to one note (or fewer if entries are small).
      2. Prefer FEWER, LARGER notes — minimum 30 content lines per note. Merge small sections into their neighbors.
      3. When in doubt, DO NOT split — keep content together in a single note.
      4. Each note should represent a coherent topic, chapter, or logical unit.
      5. Never create a note that is just a list of links, references, or a table of contents.
         The TOC itself should be merged into the first content section.
      6. Slides or pages without clear topic boundaries should be merged together.
      7. If the document has no clear structure (no headings, no TOC), return a single entry covering all lines.

      Respond ONLY with a valid JSON array, no other text:
      [{"title": "Chapter title", "start_line": 0, "end_line": 45, "reason": "Brief reason"}]

      Line numbers are 0-indexed. The last entry's end_line must equal the total lines minus 1.
      Entries must be contiguous (no gaps, no overlaps).
      If the document should NOT be split, return a single entry covering all lines.
    PROMPT

    PROMPTS = {
      "grammar_review" => GRAMMAR_REVIEW_PROMPT,
      "rewrite" => REWRITE_PROMPT,
      "translate" => TRANSLATE_PROMPT,
      "seed_note" => SEED_NOTE_PROMPT,
      "import_analyze" => IMPORT_ANALYZE_PROMPT
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
