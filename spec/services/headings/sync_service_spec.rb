require "rails_helper"

RSpec.describe Headings::SyncService do
  let(:note) { create(:note, :with_head_revision) }

  it "creates headings from markdown content" do
    content = "# Title\n## Section A\n### Subsection"

    described_class.call(note:, content:)

    headings = note.note_headings.order(:position)
    expect(headings.size).to eq(3)
    expect(headings.map(&:text)).to eq(["Title", "Section A", "Subsection"])
    expect(headings.map(&:level)).to eq([1, 2, 3])
    expect(headings.map(&:slug)).to eq(["title", "section-a", "subsection"])
  end

  it "replaces existing headings when content changes" do
    described_class.call(note:, content: "# Old Title")
    expect(note.note_headings.count).to eq(1)

    described_class.call(note:, content: "## New Section\n## Another")
    note.reload

    expect(note.note_headings.count).to eq(2)
    expect(note.note_headings.order(:position).map(&:text)).to eq(["New Section", "Another"])
  end

  it "clears headings when content has none" do
    described_class.call(note:, content: "# Has Heading")
    expect(note.note_headings.count).to eq(1)

    described_class.call(note:, content: "Just plain text, no headings.")
    expect(note.note_headings.count).to eq(0)
  end

  it "is idempotent — same content produces same headings" do
    content = "## Heading A\n## Heading B"

    described_class.call(note:, content:)
    first_ids = note.note_headings.pluck(:slug).sort

    described_class.call(note:, content:)
    note.reload
    second_slugs = note.note_headings.pluck(:slug).sort

    expect(second_slugs).to eq(first_ids)
    expect(note.note_headings.count).to eq(2)
  end
end
