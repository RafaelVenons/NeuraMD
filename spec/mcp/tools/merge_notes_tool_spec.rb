require "rails_helper"
require "mcp"

RSpec.describe Mcp::Tools::MergeNotesTool do
  it "has correct tool metadata" do
    expect(described_class.name_value).to eq("merge_notes")
    expect(described_class.description_value).to be_present
  end

  describe ".call" do
    let!(:source) { create(:note, :with_head_revision, title: "Source Note") }
    let!(:target) { create(:note, :with_head_revision, title: "Target Note") }

    it "merges source into target" do
      response = described_class.call(
        source_slug: source.slug,
        target_slug: target.slug
      )
      data = JSON.parse(response.content.first[:text])

      expect(data["merged"]).to be true
      expect(data["source_slug"]).to eq(source.slug)
      expect(data["target_slug"]).to eq(target.slug)
      expect(data["revision_id"]).to be_present
    end

    it "soft-deletes the source note" do
      described_class.call(
        source_slug: source.slug,
        target_slug: target.slug
      )

      expect(source.reload.deleted?).to be true
    end

    it "appends source content to target" do
      source_content = source.head_revision.content_markdown
      described_class.call(
        source_slug: source.slug,
        target_slug: target.slug
      )

      target.reload
      expect(target.head_revision.content_markdown).to include(source_content)
    end

    it "retargets incoming links from source to target" do
      linker = create(:note, :with_head_revision, title: "Linker")
      link = create(:note_link, src_note: linker, dst_note: source)

      described_class.call(
        source_slug: source.slug,
        target_slug: target.slug
      )

      link.reload
      expect(link.dst_note_id).to eq(target.id)
    end

    it "creates slug redirect for source" do
      old_slug = source.slug
      described_class.call(
        source_slug: source.slug,
        target_slug: target.slug
      )

      redirect = SlugRedirect.find_by(slug: old_slug)
      expect(redirect).to be_present
      expect(redirect.note_id).to eq(target.id)
    end

    it "returns error when source not found" do
      response = described_class.call(
        source_slug: "nonexistent",
        target_slug: target.slug
      )

      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("Source note not found")
    end

    it "returns error when target not found" do
      response = described_class.call(
        source_slug: source.slug,
        target_slug: "nonexistent"
      )

      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("Target note not found")
    end

    it "returns error when merging note into itself" do
      response = described_class.call(
        source_slug: source.slug,
        target_slug: source.slug
      )

      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("Cannot merge a note into itself")
    end

    it "succeeds when target body contains a wikilink to source" do
      Notes::CheckpointService.call(
        note: target,
        content: "Ver [[Source|c:#{source.id}]]"
      )

      response = described_class.call(
        source_slug: source.slug,
        target_slug: target.slug
      )
      data = JSON.parse(response.content.first[:text])

      expect(response.error?).to be false
      expect(data["merged"]).to be true
    end

    it "returns a readable error when MergeService raises RecordInvalid" do
      invalid_record = SlugRedirect.new
      invalid_record.errors.add(:slug, "já existe no banco")
      allow(Notes::MergeService).to receive(:call)
        .and_raise(ActiveRecord::RecordInvalid.new(invalid_record))

      response = described_class.call(
        source_slug: source.slug,
        target_slug: target.slug
      )

      expect(response.error?).to be true
      text = response.content.first[:text]
      expect(text).not_to include("Translation missing")
      expect(text).to include("já existe")
    end

    it "follows slug redirects for source" do
      old_slug = "old-source-slug"
      SlugRedirect.create!(slug: old_slug, note: source)

      response = described_class.call(
        source_slug: old_slug,
        target_slug: target.slug
      )
      data = JSON.parse(response.content.first[:text])

      expect(data["merged"]).to be true
    end
  end
end
