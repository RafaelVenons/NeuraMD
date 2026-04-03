require "rails_helper"

RSpec.describe CanvasNode do
  describe "validations" do
    it "validates node_type inclusion" do
      node = build(:canvas_node, node_type: "invalid")
      expect(node).not_to be_valid
      expect(node.errors[:node_type]).to be_present
    end

    it "accepts all valid node types" do
      %w[note text image link group].each do |type|
        node = build(:canvas_node, node_type: type)
        node.note = create(:note) if type == "note"
        expect(node).to be_valid, "expected #{type} to be valid"
      end
    end

    it "requires note for note-type nodes" do
      node = build(:canvas_node, node_type: "note", note: nil)
      expect(node).not_to be_valid
      expect(node.errors[:note]).to be_present
    end

    it "does not require note for text-type nodes" do
      node = build(:canvas_node, node_type: "text", note: nil)
      expect(node).to be_valid
    end
  end

  describe "associations" do
    it "destroys outgoing edges on delete" do
      doc = create(:canvas_document)
      source = create(:canvas_node, canvas_document: doc)
      target = create(:canvas_node, canvas_document: doc)
      create(:canvas_edge, canvas_document: doc, source_node: source, target_node: target)

      expect { source.destroy! }.to change(CanvasEdge, :count).by(-1)
    end

    it "destroys incoming edges on delete" do
      doc = create(:canvas_document)
      source = create(:canvas_node, canvas_document: doc)
      target = create(:canvas_node, canvas_document: doc)
      create(:canvas_edge, canvas_document: doc, source_node: source, target_node: target)

      expect { target.destroy! }.to change(CanvasEdge, :count).by(-1)
    end
  end
end
