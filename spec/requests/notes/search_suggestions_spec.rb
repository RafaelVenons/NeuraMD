require "rails_helper"

RSpec.describe "Search suggestions", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /notes/search_suggestions" do
    it "returns tag names when operator is tag" do
      create(:tag, name: "neurociencia")
      create(:tag, name: "cardiologia")

      get search_suggestions_notes_path(operator: "tag"), headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["suggestions"]).to include("neurociencia", "cardiologia")
    end

    it "returns property keys when operator is prop" do
      PropertyDefinition.create!(key: "status", value_type: "enum", config: {"options" => %w[draft done]})
      PropertyDefinition.create!(key: "kind", value_type: "enum", config: {"options" => %w[reference journal]})

      get search_suggestions_notes_path(operator: "prop"), headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["suggestions"]).to include("status", "kind")
    end

    it "returns enum options when operator is status" do
      PropertyDefinition.create!(key: "status", value_type: "enum", config: {"options" => %w[draft done published]})

      get search_suggestions_notes_path(operator: "status"), headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["suggestions"]).to include("draft", "done", "published")
    end

    it "returns empty array for unknown operator" do
      get search_suggestions_notes_path(operator: "xyz"), headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["suggestions"]).to eq([])
    end

    it "returns empty array when no operator specified" do
      get search_suggestions_notes_path, headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["suggestions"]).to eq([])
    end
  end
end
