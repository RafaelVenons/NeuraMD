require "rails_helper"

RSpec.describe Tentacles::TodosService do
  let(:note) do
    create(:note, title: "Tentacle Note").tap do |n|
      rev = create(:note_revision, note: n, content_markdown: initial_body)
      n.update_columns(head_revision_id: rev.id)
    end
  end

  describe ".read" do
    let(:initial_body) { "Intro\n\n## Todos\n\n- [ ] a\n- [x] b\n" }

    it "returns the current todos parsed from the note body" do
      expect(described_class.read(note)).to eq([
        { text: "a", done: false },
        { text: "b", done: true }
      ])
    end
  end

  describe ".write" do
    let(:initial_body) { "Intro\n\n## Todos\n\n- [ ] old\n" }

    it "persists the new todos via a checkpoint and preserves surrounding content" do
      expect {
        described_class.write(note: note, todos: [{ text: "new", done: true }])
      }.to change { note.reload.note_revisions.where(revision_kind: :checkpoint).count }.by(1)

      expect(described_class.read(note.reload)).to eq([{ text: "new", done: true }])
      expect(note.head_revision.content_markdown).to include("Intro")
    end

    it "returns the parsed todos for the new revision" do
      result = described_class.write(note: note, todos: [{ text: "x", done: false }])
      expect(result).to eq([{ text: "x", done: false }])
    end

    it "skips checkpoint when todos are unchanged" do
      expect {
        described_class.write(note: note, todos: [{ text: "old", done: false }])
      }.not_to change { note.reload.note_revisions.count }
    end

    it "normalizes loose input (strings for done, missing keys)" do
      result = described_class.write(note: note, todos: [
        { "text" => "aaa", "done" => "true" },
        { text: "bbb" }
      ])
      expect(result).to eq([
        { text: "aaa", done: true },
        { text: "bbb", done: false }
      ])
    end

    it "drops entries with blank text" do
      result = described_class.write(note: note, todos: [
        { text: "  ", done: false },
        { text: "keep", done: false }
      ])
      expect(result).to eq([{ text: "keep", done: false }])
    end
  end
end
