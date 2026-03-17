require "rails_helper"

RSpec.describe Links::PromiseExtractService do
  describe ".call" do
    it "returns empty array when there are no promise wikilinks" do
      expect(described_class.call("Sem promessas aqui")).to eq([])
    end

    it "extracts simple promise wikilinks without uuid" do
      result = described_class.call("Criar [[Mapa Mental]] depois.")
      expect(result).to eq(["Mapa Mental"])
    end

    it "deduplicates repeated promise titles case-insensitively" do
      content = "[[Mapa Mental]] e [[ mapa mental ]]"
      expect(described_class.call(content)).to eq(["Mapa Mental"])
    end

    it "ignores wikilinks with explicit uuid payloads" do
      uuid = SecureRandom.uuid
      content = "[[Destino|#{uuid}]] e [[Outro|b:#{uuid}]]"
      expect(described_class.call(content)).to eq([])
    end
  end
end
