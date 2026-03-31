require "rails_helper"
require "mcp"

RSpec.describe Mcp::Tools::NoteGraphTool do
  let!(:center) { create(:note, :with_head_revision, title: "Nota central") }
  let!(:child) { create(:note, :with_head_revision, title: "Nota filha") }
  let!(:sibling) { create(:note, :with_head_revision, title: "Nota irmã") }

  let!(:link1) do
    create(:note_link,
      src_note: center, dst_note: child,
      hier_role: "target_is_child",
      created_in_revision: center.head_revision)
  end

  let!(:link2) do
    create(:note_link,
      src_note: center, dst_note: sibling,
      hier_role: "same_level",
      created_in_revision: center.head_revision)
  end

  it "has correct tool metadata" do
    expect(described_class.name_value).to eq("note_graph")
    expect(described_class.description_value).to be_present
  end

  it "returns center note and its links" do
    response = described_class.call(slug: center.slug)
    content = JSON.parse(response.content.first[:text])

    expect(content["center"]["slug"]).to eq(center.slug)
    expect(content["center"]["title"]).to eq("Nota central")
    expect(content["links"].length).to eq(2)
  end

  it "includes link role and target info" do
    response = described_class.call(slug: center.slug)
    content = JSON.parse(response.content.first[:text])

    child_link = content["links"].find { |l| l["target_slug"] == child.slug }
    expect(child_link["role"]).to eq("target_is_child")
    expect(child_link["target_title"]).to eq("Nota filha")
  end

  it "includes incoming links" do
    incoming = create(:note_link,
      src_note: child, dst_note: center,
      hier_role: "target_is_parent",
      created_in_revision: child.head_revision)

    response = described_class.call(slug: center.slug)
    content = JSON.parse(response.content.first[:text])

    expect(content["links"].length).to eq(3)
  end

  it "returns error for non-existent slug" do
    response = described_class.call(slug: "nao-existe")
    expect(response.error?).to be true
  end

  it "returns empty links for isolated note" do
    isolated = create(:note, :with_head_revision, title: "Isolada")
    response = described_class.call(slug: isolated.slug)
    content = JSON.parse(response.content.first[:text])

    expect(content["center"]["title"]).to eq("Isolada")
    expect(content["links"]).to be_empty
  end
end
