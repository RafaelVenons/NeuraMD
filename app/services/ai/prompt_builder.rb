require_relative "error"

module Ai
  class PromptBuilder
    PROMPTS = {
      "grammar_review" => <<~PROMPT,
        You are a grammar and spelling corrector.
        Fix only grammar, spelling, punctuation, and obvious typos.
        Preserve the original meaning, tone, structure, and Markdown formatting.
        Do not explain your changes.
        Return only the corrected text.
      PROMPT
      "suggest" => <<~PROMPT,
        You are an editorial assistant.
        Improve clarity, flow, and readability while preserving meaning and Markdown formatting.
        Keep the text concise and natural.
        Do not explain your changes.
        Return only the revised text.
      PROMPT
      "rewrite" => <<~PROMPT
        You are a rewriting assistant.
        Rewrite the text to be clearer and more polished while preserving intent and Markdown formatting.
        Do not add explanations.
        Return only the rewritten text.
      PROMPT
    }.freeze

    def self.system_prompt(capability:, language: nil)
      prompt = PROMPTS.fetch(capability.to_s) do
        raise InvalidCapabilityError, "Capability de IA invalida."
      end

      return prompt if language.blank?
      "#{prompt}\n\nPreferred language of the output: #{language}."
    end
  end
end
