require "rails_helper"

RSpec.describe NoteView do
  describe "validations" do
    it "requires name" do
      view = build(:note_view, name: "")
      expect(view).not_to be_valid
      expect(view.errors[:name]).to be_present
    end

    it "validates display_type inclusion" do
      view = build(:note_view, display_type: "grid")
      expect(view).not_to be_valid
      expect(view.errors[:display_type]).to be_present
    end

    it "accepts valid display types" do
      %w[table card list].each do |type|
        view = build(:note_view, display_type: type)
        expect(view).to be_valid
      end
    end

    it "validates sort_config shape" do
      view = build(:note_view, sort_config: {"field" => 123})
      expect(view).not_to be_valid
    end

    it "validates sort_config direction" do
      view = build(:note_view, sort_config: {"field" => "title", "direction" => "sideways"})
      expect(view).not_to be_valid
    end

    it "accepts valid sort_config" do
      view = build(:note_view, sort_config: {"field" => "title", "direction" => "asc"})
      expect(view).to be_valid
    end

    it "accepts empty sort_config" do
      view = build(:note_view, sort_config: {})
      expect(view).to be_valid
    end

    it "validates columns is an array of strings" do
      view = build(:note_view, columns: [1, 2])
      expect(view).not_to be_valid
    end

    it "accepts valid columns" do
      view = build(:note_view, columns: ["title", "status", "created_at"])
      expect(view).to be_valid
    end
  end

  describe "#parsed_filter" do
    it "returns a parsed DSL result" do
      view = build(:note_view, filter_query: "tag:neuro status:draft")
      result = view.parsed_filter
      expect(result.tokens.size).to eq(2)
      expect(result.tokens.map(&:operator)).to eq([:tag, :status])
    end

    it "memoizes the result" do
      view = build(:note_view, filter_query: "tag:x")
      expect(view.parsed_filter).to equal(view.parsed_filter)
    end
  end

  describe "#sort_field / #sort_direction" do
    it "defaults to updated_at desc" do
      view = build(:note_view, sort_config: {})
      expect(view.sort_field).to eq("updated_at")
      expect(view.sort_direction).to eq(:desc)
    end

    it "reads from sort_config" do
      view = build(:note_view, sort_config: {"field" => "title", "direction" => "asc"})
      expect(view.sort_field).to eq("title")
      expect(view.sort_direction).to eq(:asc)
    end
  end

  describe ".ordered" do
    it "orders by position then name" do
      c = create(:note_view, name: "Charlie", position: 1)
      a = create(:note_view, name: "Alpha", position: 0)
      b = create(:note_view, name: "Beta", position: 0)

      expect(NoteView.ordered.pluck(:id)).to eq([a.id, b.id, c.id])
    end
  end
end
