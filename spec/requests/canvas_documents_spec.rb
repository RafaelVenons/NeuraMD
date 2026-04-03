require "rails_helper"

RSpec.describe "CanvasDocuments", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "POST /canvas" do
    it "creates a canvas document and returns JSON" do
      post canvas_documents_path, params: {
        canvas_document: {name: "My Canvas"}
      }, as: :json

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["name"]).to eq("My Canvas")
      expect(body["id"]).to be_present
    end

    it "returns errors for invalid params" do
      post canvas_documents_path, params: {
        canvas_document: {name: ""}
      }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"]).to be_present
    end
  end

  describe "PATCH /canvas/:id" do
    it "updates canvas name" do
      doc = create(:canvas_document, name: "Old Name")

      patch canvas_document_path(doc), params: {
        canvas_document: {name: "New Name"}
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["name"]).to eq("New Name")
    end

    it "updates viewport" do
      doc = create(:canvas_document)

      patch canvas_document_path(doc), params: {
        canvas_document: {viewport: {x: 100, y: 200, zoom: 1.5}.to_json}
      }, as: :json

      expect(response).to have_http_status(:ok)
      doc.reload
      expect(doc.viewport_x).to eq(100)
      expect(doc.viewport_zoom).to eq(1.5)
    end
  end

  describe "DELETE /canvas/:id" do
    it "destroys the canvas document" do
      doc = create(:canvas_document)

      expect { delete canvas_document_path(doc), as: :json }
        .to change(CanvasDocument, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end

  describe "authentication" do
    before { sign_out user }

    it "redirects unauthenticated requests" do
      get canvas_documents_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
