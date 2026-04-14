require "rails_helper"
require "mcp"

RSpec.describe Mcp::Tools::RecentChangesTool do
  let!(:old_note) do
    n = create(:note, :with_head_revision, title: "Antiga")
    n.head_revision.update_columns(created_at: 3.days.ago, updated_at: 3.days.ago)
    n
  end

  let!(:mid_note) do
    n = create(:note, :with_head_revision, title: "Media")
    n.head_revision.update_columns(created_at: 1.day.ago, updated_at: 1.day.ago)
    n
  end

  let!(:new_note) do
    n = create(:note, :with_head_revision, title: "Recente")
    n.head_revision.update_columns(created_at: 1.hour.ago, updated_at: 1.hour.ago)
    n
  end

  it "has correct tool metadata" do
    expect(described_class.name_value).to eq("recent_changes")
    expect(described_class.description_value).to be_present
  end

  it "returns notes ordered by head revision created_at desc" do
    response = described_class.call
    titles = JSON.parse(response.content.first[:text])["notes"].map { |n| n["title"] }
    expect(titles).to eq(%w[Recente Media Antiga])
  end

  it "respects the limit parameter" do
    response = described_class.call(limit: 2)
    notes = JSON.parse(response.content.first[:text])["notes"]
    expect(notes.length).to eq(2)
    expect(notes.map { |n| n["title"] }).to eq(%w[Recente Media])
  end

  it "excludes soft-deleted notes" do
    create(:note, :deleted, title: "Deletada")
    response = described_class.call
    titles = JSON.parse(response.content.first[:text])["notes"].map { |n| n["title"] }
    expect(titles).not_to include("Deletada")
  end

  it "filters by since timestamp" do
    response = described_class.call(since: 2.days.ago.iso8601)
    titles = JSON.parse(response.content.first[:text])["notes"].map { |n| n["title"] }
    expect(titles).to contain_exactly("Recente", "Media")
  end

  it "returns error for invalid since" do
    response = described_class.call(since: "not-a-date")
    expect(response.error?).to be true
    expect(response.content.first[:text]).to include("Invalid 'since'")
  end

  it "filters by tag when provided" do
    tag = create(:tag, name: "featured")
    new_note.tags << tag
    response = described_class.call(tag: "featured")
    titles = JSON.parse(response.content.first[:text])["notes"].map { |n| n["title"] }
    expect(titles).to eq(["Recente"])
  end

  it "returns empty list for unknown tag" do
    response = described_class.call(tag: "nonexistent")
    data = JSON.parse(response.content.first[:text])
    expect(data["notes"]).to eq([])
  end

  it "returns changed_at in iso8601 format" do
    response = described_class.call(limit: 1)
    note = JSON.parse(response.content.first[:text])["notes"].first
    expect { Time.iso8601(note["changed_at"]) }.not_to raise_error
  end

  it "includes tag names on each note" do
    tag = create(:tag, name: "topic-x")
    new_note.tags << tag
    response = described_class.call(limit: 1)
    note = JSON.parse(response.content.first[:text])["notes"].first
    expect(note["tags"]).to include("topic-x")
  end

  it "caps limit at 100" do
    response = described_class.call(limit: 5000)
    data = JSON.parse(response.content.first[:text])
    expect(data["notes"].length).to be <= 100
  end
end
