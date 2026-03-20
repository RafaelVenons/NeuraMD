require "rails_helper"

RSpec.describe Ai::PromptBuilder do
  describe ".system_prompt" do
    it "builds the grammar prompt with preferred language" do
      prompt = described_class.system_prompt(capability: "grammar_review", language: "pt-BR")

      expect(prompt).to include("grammar and spelling corrector")
      expect(prompt).to include("Preferred language of the output: pt-BR.")
    end

    it "builds the suggest prompt" do
      prompt = described_class.system_prompt(capability: "suggest", language: nil)

      expect(prompt).to include("editorial assistant")
      expect(prompt).to include("Improve clarity, flow, and readability")
    end

    it "rejects unsupported capabilities" do
      expect {
        described_class.system_prompt(capability: "unknown", language: nil)
      }.to raise_error(Ai::InvalidCapabilityError, "Capability de IA invalida.")
    end
  end
end
