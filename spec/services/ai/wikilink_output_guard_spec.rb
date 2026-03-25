require "rails_helper"

RSpec.describe Ai::WikilinkOutputGuard do
  describe ".normalize!" do
    it "accepts output that preserves wikilink payloads while changing visible text" do
      uuid = SecureRandom.uuid

      result = described_class.normalize!(
        content: "[[Pai traduzido|f:#{uuid}]]",
        source_text: "[[Parent|f:#{uuid}]]"
      )

      expect(result).to eq("[[Pai traduzido|f:#{uuid}]]")
    end

    it "appends the original wikilink when the AI drops an existing payload entirely" do
      uuid = SecureRandom.uuid

      result = described_class.normalize!(
        content: "Texto sem link",
        source_text: "[[Parent|f:#{uuid}]]"
      )

      expect(result).to eq("Texto sem link [[Parent|f:#{uuid}]]")
    end

    it "appends the original wikilink when the AI rewrites an existing payload" do
      uuid = SecureRandom.uuid
      other_uuid = SecureRandom.uuid

      result = described_class.normalize!(
        content: "[[Pai|f:#{other_uuid}]]",
        source_text: "[[Pai|f:#{uuid}]]"
      )

      expect(result).to eq("[[Pai|f:#{other_uuid}]] [[Pai|f:#{uuid}]]")
    end

    it "downgrades invalid wikilink payloads in the output to plain wikilinks" do
      result = described_class.normalize!(
        content: "[[Nota|nao-e-uuid]]",
        source_text: ""
      )

      expect(result).to eq("[[Nota]]")
    end

    it "restores a missing payload when the AI keeps the wikilink title" do
      uuid = SecureRandom.uuid

      result = described_class.normalize!(
        content: "Bloco refinado com [[Referencia polida]] para leitura.",
        source_text: "Bloco [[Referencia polida|b:#{uuid}]] para reescrever."
      )

      expect(result).to eq("Bloco refinado com [[Referencia polida|b:#{uuid}]] para leitura.")
    end

    it "restores a missing payload when the AI translates the wikilink title" do
      uuid = SecureRandom.uuid

      result = described_class.normalize!(
        content: "Translated [[My friend]] content.",
        source_text: "Conteudo com [[Meu amigo|#{uuid}]]."
      )

      expect(result).to eq("Translated [[My friend|#{uuid}]] content.")
    end

    it "restores a missing payload when the AI drops the wikilink markup but keeps the title as plain text" do
      uuid = SecureRandom.uuid

      result = described_class.normalize!(
        content: "Bloco refinado com Referencia polida para leitura.",
        source_text: "Bloco com [[Referencia polida|b:#{uuid}]]."
      )

      expect(result).to eq("Bloco refinado com [[Referencia polida|b:#{uuid}]] para leitura.")
    end

    it "appends missing wikilinks at the end of the corresponding source line as a fallback" do
      first_uuid = SecureRandom.uuid
      second_uuid = SecureRandom.uuid

      result = described_class.normalize!(
        content: "Linha 1 reescrita.\nLinha 2 reescrita.",
        source_text: "Linha 1 [[Pai|f:#{first_uuid}]].\nLinha 2 [[Filho|c:#{second_uuid}]]."
      )

      expect(result).to eq(
        "Linha 1 reescrita. [[Pai|f:#{first_uuid}]]\nLinha 2 reescrita. [[Filho|c:#{second_uuid}]]"
      )
    end
  end
end
