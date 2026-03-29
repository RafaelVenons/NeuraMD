require "rails_helper"

RSpec.describe Ai::PromptBuilder do
  describe ".system_prompt" do
    describe "grammar_review" do
      subject(:prompt) { described_class.system_prompt(capability: "grammar_review", language: "pt-BR") }

      it "identifies as grammar and spelling corrector" do
        expect(prompt).to include("grammar and spelling corrector")
      end

      it "lists what to fix" do
        expect(prompt).to include("Grammar errors")
        expect(prompt).to include("Spelling mistakes")
        expect(prompt).to include("Punctuation errors")
      end

      it "lists what NOT to change" do
        expect(prompt).to include("DO NOT change")
        expect(prompt).to include("Writing style or tone")
        expect(prompt).to include("Markdown formatting")
        expect(prompt).to include("Technical terms or proper nouns")
        expect(prompt).to include("Code blocks or inline code")
      end

      it "includes wikilink preservation rules" do
        expect(prompt).to include("[[Title]]")
        expect(prompt).to include("hidden payloads are restored automatically")
      end

      it "includes preferred language" do
        expect(prompt).to include("Preferred language of the output: pt-BR.")
        expect(prompt).to include("Return the full answer only in pt-BR.")
      end
    end

    describe "rewrite (Markdown structure)" do
      subject(:prompt) { described_class.system_prompt(capability: "rewrite", language: "en") }

      it "identifies as Markdown structure assistant" do
        expect(prompt).to include("Markdown structure assistant")
      end

      it "lists allowed structural changes" do
        expect(prompt).to include("Add or adjust headings")
        expect(prompt).to include("Convert paragraphs into bullet or numbered lists")
        expect(prompt).to include("Add bold/italic emphasis")
      end

      it "forbids content changes" do
        expect(prompt).to include("DO NOT")
        expect(prompt).to include("Change, rephrase, or rewrite any of the actual text content")
        expect(prompt).to include("Fix grammar or spelling")
      end

      it "includes wikilink preservation rules" do
        expect(prompt).to include("[[Title]]")
      end
    end

    describe "translate" do
      subject(:prompt) do
        described_class.system_prompt(
          capability: "translate",
          language: "pt-BR",
          target_language: "en-US"
        )
      end

      it "identifies as translation assistant" do
        expect(prompt).to include("translation assistant")
      end

      it "includes source and target languages" do
        expect(prompt).to include("Source language: pt-BR.")
        expect(prompt).to include("Target language: en-US.")
        expect(prompt).to include("Return the full answer only in en-US.")
      end

      it "includes wikilink preservation rules" do
        expect(prompt).to include("Do not add anything after the pipe inside wikilinks")
      end
    end

    describe "seed_note" do
      subject(:prompt) { described_class.system_prompt(capability: "seed_note", language: "pt-BR") }

      it "identifies as note-seeding assistant" do
        expect(prompt).to include("note-seeding assistant")
      end

      it "emphasizes title as sole topic" do
        expect(prompt).to include("SOLE topic")
        expect(prompt).to include("Write exclusively about what the title describes")
      end

      it "warns against using source note as topic" do
        expect(prompt).to include("NEVER let the source note content become the topic")
      end

      it "forbids markdown fences" do
        expect(prompt).to include("Never wrap the answer in ```markdown fences")
      end

      it "includes preferred language" do
        expect(prompt).to include("Preferred language of the output: pt-BR.")
        expect(prompt).to include("Return the full answer only in pt-BR.")
      end
    end

    it "rejects unsupported capabilities" do
      expect {
        described_class.system_prompt(capability: "unknown", language: nil)
      }.to raise_error(Ai::InvalidCapabilityError, "Capability de IA invalida.")
    end
  end
end
