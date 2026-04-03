require "rails_helper"

RSpec.describe CanvasEdge do
  describe "validations" do
    it "validates edge_type inclusion" do
      edge = build(:canvas_edge, edge_type: "zigzag")
      expect(edge).not_to be_valid
      expect(edge.errors[:edge_type]).to be_present
    end

    it "accepts valid edge types" do
      %w[arrow line dashed].each do |type|
        edge = build(:canvas_edge, edge_type: type)
        expect(edge).to be_valid, "expected #{type} to be valid"
      end
    end

    it "prevents duplicate source-target pairs" do
      doc = create(:canvas_document)
      source = create(:canvas_node, canvas_document: doc)
      target = create(:canvas_node, canvas_document: doc)
      create(:canvas_edge, canvas_document: doc, source_node: source, target_node: target)

      duplicate = build(:canvas_edge, canvas_document: doc, source_node: source, target_node: target)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:source_node_id]).to be_present
    end

    it "allows same source with different targets" do
      doc = create(:canvas_document)
      source = create(:canvas_node, canvas_document: doc)
      target1 = create(:canvas_node, canvas_document: doc)
      target2 = create(:canvas_node, canvas_document: doc)

      create(:canvas_edge, canvas_document: doc, source_node: source, target_node: target1)
      edge2 = build(:canvas_edge, canvas_document: doc, source_node: source, target_node: target2)
      expect(edge2).to be_valid
    end
  end
end
