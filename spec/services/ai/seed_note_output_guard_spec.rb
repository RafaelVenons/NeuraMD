require "rails_helper"

RSpec.describe Ai::SeedNoteOutputGuard do
  describe ".normalize!" do
    it "unwraps a full markdown fence before saving the note body" do
      content = <<~MD
        ```markdown
        # Nota

        Corpo inicial.
        ```
      MD

      result = described_class.normalize!(content:, input_text: "prompt bruto")

      expect(result).to eq("# Nota\n\nCorpo inicial.")
    end

    it "rejects blank output after sanitization" do
      expect {
        described_class.normalize!(content: "```markdown\n\n```", input_text: "prompt bruto")
      }.to raise_error(Ai::InvalidOutputError, /voltou vazia/)
    end

    it "rejects prompt echo from the seed-note template" do
      content = <<~TEXT
        Create an initial markdown note for the new title below.

        New note title: Cardiologia
      TEXT

      expect {
        described_class.normalize!(content:, input_text: "prompt bruto")
      }.to raise_error(Ai::InvalidOutputError, /instruc/i)
    end

    it "downgrades invalid wikilink payloads instead of rejecting the seed note" do
      result = described_class.normalize!(content: "[[Nota|nao-e-uuid]]", input_text: "prompt bruto")

      expect(result).to eq("[[Nota]]")
    end

    it "keeps unbalanced wikilink brackets instead of rejecting the seed note" do
      result = described_class.normalize!(content: "[[Nota|123", input_text: "prompt bruto")

      expect(result).to eq("[[Nota|123")
    end

    it "accepts valid wikilinks with supported roles" do
      uuid = SecureRandom.uuid

      result = described_class.normalize!(
        content: "[[Pai|f:#{uuid}]]\n\n[[Filho|c:#{uuid}]]",
        input_text: "prompt bruto"
      )

      expect(result).to include("[[Pai|f:#{uuid}]]")
      expect(result).to include("[[Filho|c:#{uuid}]]")
    end
  end
end
