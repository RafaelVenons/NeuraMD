require "rails_helper"

RSpec.describe "Note property query scopes", type: :model do
  let(:user) { create(:user) }

  before do
    create(:property_definition, key: "status", value_type: "enum", config: {"options" => %w[draft review published]})
    create(:property_definition, key: "priority", value_type: "number")
  end

  def create_note_with_properties(title:, properties:)
    note = create(:note, :with_head_revision, title: title)
    Properties::SetService.call(note: note, changes: properties, author: user)
    note.reload
    note
  end

  describe ".with_property" do
    it "finds notes with a specific string property value" do
      draft = create_note_with_properties(title: "Draft Note", properties: {"status" => "draft"})
      published = create_note_with_properties(title: "Published Note", properties: {"status" => "published"})
      _no_status = create(:note, :with_head_revision, title: "No Status")

      results = Note.active.with_property("status", "draft")
      expect(results).to include(draft)
      expect(results).not_to include(published)
    end

    it "finds notes with a numeric property value" do
      high = create_note_with_properties(title: "High Priority", properties: {"priority" => 1})
      low = create_note_with_properties(title: "Low Priority", properties: {"priority" => 5})

      results = Note.active.with_property("priority", 1)
      expect(results).to include(high)
      expect(results).not_to include(low)
    end
  end

  describe ".with_property_in" do
    it "finds notes matching any of the given values" do
      draft = create_note_with_properties(title: "Draft", properties: {"status" => "draft"})
      review = create_note_with_properties(title: "Review", properties: {"status" => "review"})
      published = create_note_with_properties(title: "Published", properties: {"status" => "published"})

      results = Note.active.with_property_in("status", %w[draft review])
      expect(results).to include(draft, review)
      expect(results).not_to include(published)
    end
  end

  describe "NoteQueryService with property_filters" do
    it "filters search results by property" do
      draft = create_note_with_properties(title: "Alpha Draft", properties: {"status" => "draft"})
      published = create_note_with_properties(title: "Alpha Published", properties: {"status" => "published"})

      result = Search::NoteQueryService.call(
        scope: Note.active,
        query: "Alpha",
        property_filters: {"status" => "draft"}
      )

      expect(result.notes).to include(draft)
      expect(result.notes).not_to include(published)
    end

    it "returns filtered notes when query is blank" do
      draft = create_note_with_properties(title: "My Draft", properties: {"status" => "draft"})
      _published = create_note_with_properties(title: "My Published", properties: {"status" => "published"})

      result = Search::NoteQueryService.call(
        scope: Note.active,
        query: "",
        property_filters: {"status" => "draft"}
      )

      expect(result.notes).to include(draft)
      expect(result.notes.size).to eq(1)
    end

    it "works without property_filters (backwards compatible)" do
      create(:note, :with_head_revision, title: "Any Note")

      result = Search::NoteQueryService.call(
        scope: Note.active,
        query: "Any"
      )

      expect(result.notes.size).to eq(1)
    end
  end
end
