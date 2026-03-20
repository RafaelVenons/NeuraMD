require "rails_helper"

RSpec.describe Ai::ModelRouter do
  describe ".route" do
    it "routes short grammar reviews to a smaller ollama model" do
      selection = described_class.route(
        provider_name: "ollama",
        configured_model: "qwen2.5:1.5b",
        capability: "grammar_review",
        text: "Texto curto com erro.",
        language: "pt-BR"
      )

      expect(selection).to include(
        model: "qwen2.5:0.5b",
        selection_strategy: "automatic",
        selection_reason: "grammar_short"
      )
    end

    it "routes long rewrites to a larger quality-oriented ollama model" do
      selection = described_class.route(
        provider_name: "ollama",
        configured_model: "qwen2.5:1.5b",
        capability: "rewrite",
        text: "a" * 2_000,
        language: "pt-BR"
      )

      expect(selection).to include(
        model: "llama3.2:3b",
        selection_reason: "rewrite_long"
      )
    end

    it "routes short pt-en translations to qwen2:1.5b" do
      selection = described_class.route(
        provider_name: "ollama",
        configured_model: "qwen2.5:1.5b",
        capability: "translate",
        text: "O paciente melhorou depois do ajuste da medicacao.",
        language: "pt-BR",
        target_language: "en"
      )

      expect(selection).to include(
        model: "qwen2:1.5b",
        selection_reason: "translate_pt_en_short"
      )
    end

    it "routes note seeding to the dedicated ollama model lane" do
      selection = described_class.route(
        provider_name: "ollama",
        configured_model: "qwen2.5:1.5b",
        capability: "seed_note",
        text: "a" * 2_200,
        language: "pt-BR"
      )

      expect(selection).to include(
        model: "qwen2.5:3b",
        selection_reason: "seed_note_long"
      )
    end

    it "falls back to the configured model for non-ollama providers" do
      selection = described_class.route(
        provider_name: "openai",
        configured_model: "gpt-4o-mini",
        capability: "grammar_review",
        text: "Texto com erro.",
        language: "pt-BR"
      )

      expect(selection).to include(
        model: "gpt-4o-mini",
        selection_strategy: "configured_default",
        selection_reason: "provider_non_ollama"
      )
    end
  end
end
