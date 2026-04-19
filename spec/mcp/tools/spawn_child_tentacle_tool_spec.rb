require "rails_helper"
require "mcp"

RSpec.describe Mcp::Tools::SpawnChildTentacleTool do
  it "has correct tool metadata" do
    expect(described_class.name_value).to eq("spawn_child_tentacle")
    expect(described_class.description_value).to be_present
  end

  describe ".call" do
    let!(:parent) { create(:note, :with_head_revision, title: "Parent Tentacle") }

    it "creates a child note linked to the parent and returns metadata" do
      response = described_class.call(parent_slug: parent.slug, title: "New Child")
      data = JSON.parse(response.content.first[:text])

      expect(data["spawned"]).to be true
      expect(data["parent_slug"]).to eq(parent.slug)
      expect(data["tentacle_url"]).to eq("/notes/#{data["slug"]}/tentacle")

      child = Note.find(data["id"])
      expect(child.title).to eq("New Child")
      expect(child.head_revision.content_markdown).to include("[[Parent Tentacle|f:#{parent.id}]]")
      expect(child.head_revision.content_markdown).to include("## Todos")
      expect(child.tags.pluck(:name)).to include("tentacle")
    end

    it "creates an outgoing father link to the parent" do
      response = described_class.call(parent_slug: parent.slug, title: "Linked Child")
      data = JSON.parse(response.content.first[:text])
      child = Note.find(data["id"])

      link = child.outgoing_links.first
      expect(link.dst_note_id).to eq(parent.id)
      expect(link.hier_role).to eq("target_is_parent")
    end

    it "embeds the optional description between link and Todos heading" do
      response = described_class.call(
        parent_slug: parent.slug,
        title: "With Desc",
        description: "Investigate the data export pipeline."
      )
      data = JSON.parse(response.content.first[:text])
      body = Note.find(data["id"]).head_revision.content_markdown

      expect(body).to match(/\[\[Parent Tentacle\|f:.*\]\]\s+Investigate the data export pipeline\.\s+## Todos/m)
    end

    it "applies extra tags alongside tentacle" do
      response = described_class.call(
        parent_slug: parent.slug,
        title: "Tagged",
        extra_tags: "research, urgent"
      )
      data = JSON.parse(response.content.first[:text])

      expect(data["tags"]).to include("tentacle", "research", "urgent")
    end

    it "returns error when parent does not exist" do
      response = described_class.call(parent_slug: "missing", title: "Orphan")
      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("Parent note not found")
    end

    it "returns error when title is blank" do
      response = described_class.call(parent_slug: parent.slug, title: "   ")
      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("Title")
    end
  end
end
