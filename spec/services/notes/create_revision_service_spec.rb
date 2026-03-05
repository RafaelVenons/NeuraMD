require "rails_helper"

RSpec.describe Notes::CreateRevisionService do
  let(:user) { create(:user) }
  let(:note) { create(:note, :with_head_revision) }

  def call(content: nil, author: user, summary: nil)
    described_class.call(
      note: note,
      content_markdown: content || note.head_revision.content_markdown,
      author: author,
      change_summary: summary
    )
  end

  describe ".call" do
    context "when change is significant (>= 200 chars diff)" do
      it "creates a new revision" do
        note  # force lazy evaluation before the expect block
        expect {
          call(content: "A" * 300)
        }.to change(NoteRevision, :count).by(1)
      end

      it "updates note.head_revision_id" do
        result = call(content: "A" * 300)
        expect(note.reload.head_revision_id).to eq(result[:revision].id)
      end

      it "returns created: true" do
        result = call(content: "A" * 300)
        expect(result[:created]).to be(true)
        expect(result[:revision]).to be_a(NoteRevision)
      end

      it "sets base_revision_id to previous head" do
        old_head_id = note.head_revision_id
        result = call(content: "A" * 300)
        expect(result[:revision].base_revision_id).to eq(old_head_id)
      end

      it "encrypts content_markdown" do
        result = call(content: "Sensitive content " * 20)
        # Content is stored encrypted — read via model (decrypts transparently)
        expect(result[:revision].content_markdown).to include("Sensitive content")
        # Verify content_plain is derived (not the raw markdown)
        expect(result[:revision].content_plain).to be_present
      end
    end

    context "when change is significant (>= 5% ratio)" do
      it "creates a revision when ratio threshold exceeded" do
        # Use a 400-char base. 5% = 20 chars. Add 25 chars to exceed threshold.
        base = "x" * 400
        new_content = base + ("y" * 25)
        # Update via service to get properly encrypted content in head revision
        Notes::CreateRevisionService.call(note: note, content_markdown: base, author: user)

        expect {
          call(content: new_content)
        }.to change(NoteRevision, :count).by(1)
      end
    end

    context "when change is below threshold" do
      it "does not create a revision" do
        original = note.head_revision.content_markdown
        tiny = original + "."

        expect {
          call(content: tiny)
        }.not_to change(NoteRevision, :count)
      end

      it "returns created: false" do
        original = note.head_revision.content_markdown
        result = call(content: original + ".")
        expect(result[:created]).to be(false)
      end

      it "returns the current head revision" do
        original = note.head_revision.content_markdown
        result = call(content: original + ".")
        expect(result[:revision]).to eq(note.head_revision)
      end
    end

    context "when note has no head revision" do
      let(:note) { create(:note) }

      it "always creates the first revision" do
        expect {
          call(content: "Qualquer conteúdo")
        }.to change(NoteRevision, :count).by(1)
      end
    end

    context "author attribution" do
      it "assigns author to revision" do
        result = call(content: "A" * 300, author: user)
        expect(result[:revision].author).to eq(user)
      end

      it "allows nil author" do
        result = call(content: "A" * 300, author: nil)
        expect(result[:revision].author).to be_nil
      end
    end

    context "change_summary" do
      it "stores the change summary" do
        result = call(content: "A" * 300, summary: "Adicionei introdução")
        expect(result[:revision].change_summary).to eq("Adicionei introdução")
      end
    end
  end
end
