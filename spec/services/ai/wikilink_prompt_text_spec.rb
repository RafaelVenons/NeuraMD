require "rails_helper"

RSpec.describe Ai::WikilinkPromptText do
  describe ".normalize" do
    it "removes valid wikilink payloads while preserving the double-bracket structure" do
      uuid = SecureRandom.uuid

      result = described_class.normalize("Texto [[Pai|f:#{uuid}]] e [[Filho|#{uuid}]].")

      expect(result).to eq("Texto [[Pai]] e [[Filho]].")
    end

    it "keeps wikilinks with invalid payloads unchanged" do
      result = described_class.normalize("Texto [[Pai|nao-e-uuid]].")

      expect(result).to eq("Texto [[Pai|nao-e-uuid]].")
    end
  end
end
