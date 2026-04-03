require "rails_helper"

RSpec.describe "CanvasEdges", type: :request do
  let(:user) { create(:user) }
  let(:canvas_document) { create(:canvas_document) }
  let(:source_node) { create(:canvas_node, canvas_document: canvas_document) }
  let(:target_node) { create(:canvas_node, canvas_document: canvas_document) }

  before { sign_in user }

  describe "POST /canvas/:canvas_document_id/canvas_edges" do
    it "creates an edge" do
      post canvas_document_canvas_edges_path(canvas_document), params: {
        canvas_edge: {
          source_node_id: source_node.id,
          target_node_id: target_node.id,
          edge_type: "arrow",
          label: "relates to"
        }
      }, as: :json

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["source_node_id"]).to eq(source_node.id)
      expect(body["target_node_id"]).to eq(target_node.id)
      expect(body["label"]).to eq("relates to")
    end

    it "prevents duplicate edges" do
      create(:canvas_edge, canvas_document: canvas_document,
        source_node: source_node, target_node: target_node)

      post canvas_document_canvas_edges_path(canvas_document), params: {
        canvas_edge: {source_node_id: source_node.id, target_node_id: target_node.id}
      }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /canvas/:canvas_document_id/canvas_edges/:id" do
    it "updates edge type" do
      edge = create(:canvas_edge, canvas_document: canvas_document,
        source_node: source_node, target_node: target_node, edge_type: "arrow")

      patch canvas_document_canvas_edge_path(canvas_document, edge), params: {
        canvas_edge: {edge_type: "dashed"}
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["edge_type"]).to eq("dashed")
    end
  end

  describe "DELETE /canvas/:canvas_document_id/canvas_edges/:id" do
    it "destroys the edge" do
      edge = create(:canvas_edge, canvas_document: canvas_document,
        source_node: source_node, target_node: target_node)

      expect { delete canvas_document_canvas_edge_path(canvas_document, edge), as: :json }
        .to change(CanvasEdge, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end
end
