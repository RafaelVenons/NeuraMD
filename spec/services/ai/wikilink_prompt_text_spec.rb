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

    # ── EPIC-03.2: heading fragment ──────────────────────────

    it "strips heading fragment along with UUID payload" do
      uuid = SecureRandom.uuid

      result = described_class.normalize("See [[Nota|#{uuid}#introduction]] and [[Pai|f:#{uuid}#overview]].")

      expect(result).to eq("See [[Nota]] and [[Pai]].")
    end
  end
end
