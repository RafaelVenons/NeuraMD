require "rails_helper"
require "mcp"

RSpec.describe Mcp::Tools::FindAnemicNotesTool do
  it "has correct tool metadata" do
    expect(described_class.name_value).to eq("find_anemic_notes")
    expect(described_class.description_value).to be_present
  end

  describe ".call" do
    it "detects anemic notes below threshold" do
      note = create(:note, title: "Short Note")
      rev = create(:note_revision, note: note, content_markdown: "Line one\nLine two\nLine three")
      note.update_columns(head_revision_id: rev.id)

      response = described_class.call(max_lines: 10)
      data = JSON.parse(response.content.first[:text])

      slugs = data["anemic_notes"].map { |n| n["slug"] }
      expect(slugs).to include(note.slug)
      anemic = data["anemic_notes"].find { |n| n["slug"] == note.slug }
      expect(anemic["content_lines"]).to eq(3)
    end

    it "excludes notes above threshold" do
      note = create(:note, title: "Dense Note")
      content = (1..15).map { |i| "Line #{i} with content" }.join("\n")
      rev = create(:note_revision, note: note, content_markdown: content)
      note.update_columns(head_revision_id: rev.id)

      response = described_class.call(max_lines: 10)
      data = JSON.parse(response.content.first[:text])

      slugs = data["anemic_notes"].map { |n| n["slug"] }
      expect(slugs).not_to include(note.slug)
    end

    it "excludes metadata lines from count" do
      note = create(:note, title: "Metadata Heavy")
      content = <<~MD
        Origem: import-batch-1
        Profundidade: 3
        Trilha: Plan > Fase 1
        Pai: nota-pai
        ---
        <!-- comment -->
        Linha-guia: algo
        Temas: tema1, tema2

        Real content line one
        Real content line two
      MD
      rev = create(:note_revision, note: note, content_markdown: content)
      note.update_columns(head_revision_id: rev.id)

      response = described_class.call(max_lines: 10)
      data = JSON.parse(response.content.first[:text])

      anemic = data["anemic_notes"].find { |n| n["slug"] == note.slug }
      expect(anemic).to be_present
      expect(anemic["content_lines"]).to eq(2)
    end

    it "filters by tag" do
      tag = Tag.find_or_create_by!(name: "testfilter", tag_scope: "note")

      matching = create(:note, title: "Tagged Anemic")
      rev1 = create(:note_revision, note: matching, content_markdown: "Short")
      matching.update_columns(head_revision_id: rev1.id)
      matching.tags << tag

      other = create(:note, title: "Untagged Anemic")
      rev2 = create(:note_revision, note: other, content_markdown: "Also short")
      other.update_columns(head_revision_id: rev2.id)

      response = described_class.call(tag: "testfilter")
      data = JSON.parse(response.content.first[:text])

      slugs = data["anemic_notes"].map { |n| n["slug"] }
      expect(slugs).to include(matching.slug)
      expect(slugs).not_to include(other.slug)
    end

    it "suggests parent as merge target when parent link exists" do
      parent = create(:note, :with_head_revision, title: "Parent Note")
      child = create(:note, title: "Child Anemic")
      rev = create(:note_revision, note: child, content_markdown: "Tiny")
      child.update_columns(head_revision_id: rev.id)
      create(:note_link, src_note: child, dst_note: parent, hier_role: "target_is_parent")

      response = described_class.call(max_lines: 10)
      data = JSON.parse(response.content.first[:text])

      anemic = data["anemic_notes"].find { |n| n["slug"] == child.slug }
      expect(anemic["merge_target"]).to be_present
      expect(anemic["merge_target"]["slug"]).to eq(parent.slug)
      expect(anemic["merge_target"]["relation"]).to eq("parent")
    end

    it "suggests incoming link as merge target when no parent" do
      referrer = create(:note, :with_head_revision, title: "Referrer Note")
      orphan = create(:note, title: "Orphan Anemic")
      rev = create(:note_revision, note: orphan, content_markdown: "Tiny")
      orphan.update_columns(head_revision_id: rev.id)
      create(:note_link, src_note: referrer, dst_note: orphan)

      response = described_class.call(max_lines: 10)
      data = JSON.parse(response.content.first[:text])

      anemic = data["anemic_notes"].find { |n| n["slug"] == orphan.slug }
      expect(anemic["merge_target"]).to be_present
      expect(anemic["merge_target"]["slug"]).to eq(referrer.slug)
      expect(anemic["merge_target"]["relation"]).to eq("linked_from")
    end

    it "returns nil merge_target when note has no links" do
      isolated = create(:note, title: "Isolated Anemic")
      rev = create(:note_revision, note: isolated, content_markdown: "Alone")
      isolated.update_columns(head_revision_id: rev.id)

      response = described_class.call(max_lines: 10)
      data = JSON.parse(response.content.first[:text])

      anemic = data["anemic_notes"].find { |n| n["slug"] == isolated.slug }
      expect(anemic["merge_target"]).to be_nil
    end

    it "respects limit parameter" do
      5.times do |i|
        note = create(:note, title: "Anemic #{i}")
        rev = create(:note_revision, note: note, content_markdown: "Short #{i}")
        note.update_columns(head_revision_id: rev.id)
      end

      response = described_class.call(max_lines: 10, limit: 3)
      data = JSON.parse(response.content.first[:text])

      expect(data["anemic_notes"].size).to be <= 3
      expect(data["count"]).to be <= 3
    end
  end
end
