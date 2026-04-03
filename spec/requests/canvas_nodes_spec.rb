require "rails_helper"

RSpec.describe "CanvasNodes", type: :request do
  let(:user) { create(:user) }
  let(:canvas_document) { create(:canvas_document) }

  before { sign_in user }

  describe "POST /canvas/:canvas_document_id/canvas_nodes" do
    it "creates a text node" do
      post canvas_document_canvas_nodes_path(canvas_document), params: {
        canvas_node: {node_type: "text", x: 50, y: 75, data: {text: "Hello"}.to_json}
      }, as: :json

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["node_type"]).to eq("text")
      expect(body["x"]).to eq(50.0)
      expect(body["y"]).to eq(75.0)
    end

    it "creates a note node" do
      note = create(:note)

      post canvas_document_canvas_nodes_path(canvas_document), params: {
        canvas_node: {node_type: "note", note_id: note.id, x: 100, y: 200}
      }, as: :json

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["note_id"]).to eq(note.id)
      expect(body["title"]).to eq(note.title)
      expect(body["slug"]).to eq(note.slug)
    end

    it "returns errors for invalid node" do
      post canvas_document_canvas_nodes_path(canvas_document), params: {
        canvas_node: {node_type: "note", note_id: nil}
      }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /canvas/:canvas_document_id/canvas_nodes/:id" do
    it "updates node position" do
      node = create(:canvas_node, canvas_document: canvas_document)

      patch canvas_document_canvas_node_path(canvas_document, node), params: {
        canvas_node: {x: 300, y: 400}
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["x"]).to eq(300.0)
      expect(response.parsed_body["y"]).to eq(400.0)
    end
  end

  describe "DELETE /canvas/:canvas_document_id/canvas_nodes/:id" do
    it "destroys the node" do
      node = create(:canvas_node, canvas_document: canvas_document)

      expect { delete canvas_document_canvas_node_path(canvas_document, node), as: :json }
        .to change(CanvasNode, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end

  describe "PATCH /canvas/:canvas_document_id/canvas_nodes/bulk_update" do
    it "updates multiple node positions" do
      n1 = create(:canvas_node, canvas_document: canvas_document, x: 0, y: 0)
      n2 = create(:canvas_node, canvas_document: canvas_document, x: 0, y: 0)

      patch bulk_update_canvas_document_canvas_nodes_path(canvas_document), params: {
        nodes: [
          {id: n1.id, x: 100, y: 200},
          {id: n2.id, x: 300, y: 400}
        ]
      }, as: :json

      expect(response).to have_http_status(:no_content)
      expect(n1.reload.x).to eq(100.0)
      expect(n2.reload.x).to eq(300.0)
    end
  end
end
