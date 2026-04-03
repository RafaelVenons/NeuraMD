require "rails_helper"

RSpec.describe CanvasDocument do
  describe "validations" do
    it "requires name" do
      doc = build(:canvas_document, name: "")
      expect(doc).not_to be_valid
      expect(doc.errors[:name]).to be_present
    end

    it "accepts valid viewport" do
      doc = build(:canvas_document, viewport: {"x" => 10, "y" => 20, "zoom" => 1.5})
      expect(doc).to be_valid
    end

    it "rejects viewport with invalid keys" do
      doc = build(:canvas_document, viewport: {"x" => 0, "y" => 0, "zoom" => 1.0, "extra" => true})
      expect(doc).not_to be_valid
      expect(doc.errors[:viewport]).to be_present
    end

    it "rejects non-hash viewport" do
      doc = build(:canvas_document, viewport: "invalid")
      expect(doc).not_to be_valid
    end
  end

  describe "#viewport_x / #viewport_y / #viewport_zoom" do
    it "reads from viewport hash" do
      doc = build(:canvas_document, viewport: {"x" => 50, "y" => 75, "zoom" => 2.0})
      expect(doc.viewport_x).to eq(50)
      expect(doc.viewport_y).to eq(75)
      expect(doc.viewport_zoom).to eq(2.0)
    end

    it "defaults when viewport is empty" do
      doc = build(:canvas_document, viewport: {})
      expect(doc.viewport_x).to eq(0)
      expect(doc.viewport_y).to eq(0)
      expect(doc.viewport_zoom).to eq(1.0)
    end
  end

  describe ".ordered" do
    it "orders by position then name" do
      c = create(:canvas_document, name: "Charlie", position: 1)
      a = create(:canvas_document, name: "Alpha", position: 0)
      b = create(:canvas_document, name: "Beta", position: 0)

      expect(CanvasDocument.ordered.pluck(:id)).to eq([a.id, b.id, c.id])
    end
  end

  describe "associations" do
    it "destroys nodes on delete" do
      doc = create(:canvas_document)
      create(:canvas_node, canvas_document: doc)

      expect { doc.destroy! }.to change(CanvasNode, :count).by(-1)
    end

    it "destroys edges on delete" do
      doc = create(:canvas_document)
      create(:canvas_edge, canvas_document: doc)

      expect { doc.destroy! }.to change(CanvasEdge, :count).by(-1)
    end
  end
end
