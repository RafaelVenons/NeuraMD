require "rails_helper"

RSpec.describe "API property definitions", type: :request do
  let(:user) { create(:user) }

  describe "GET /api/property_definitions" do
    it "returns 401 envelope when signed out" do
      get "/api/property_definitions", headers: {"ACCEPT" => "application/json"}

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to include("code" => "unauthorized")
    end

    it "lists active definitions ordered by position" do
      sign_in user
      b = create(:property_definition, key: "b", label: "B", position: 2)
      a = create(:property_definition, key: "a", label: "A", position: 1)
      create(:property_definition, :archived, key: "c", position: 3)

      get "/api/property_definitions"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["definitions"].map { |d| d["id"] }).to eq([a.id, b.id])
      expect(body["definitions"].first).to include(
        "key" => "a",
        "label" => "A",
        "value_type" => "text",
        "position" => 1,
        "system" => false
      )
    end
  end

  describe "POST /api/property_definitions" do
    it "creates a new definition with envelope on invalid" do
      sign_in user
      post "/api/property_definitions", params: {property_definition: {key: "", value_type: "text"}}

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("code" => "invalid_params")
    end

    it "creates a new definition and assigns next position" do
      sign_in user
      create(:property_definition, position: 5)

      post "/api/property_definitions", params: {
        property_definition: {key: "status", value_type: "enum", label: "Status", config: {options: %w[open closed]}}
      }

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["definition"]).to include("key" => "status", "value_type" => "enum", "position" => 6)
    end
  end

  describe "PATCH /api/property_definitions/:id" do
    it "updates label and config" do
      sign_in user
      definition = create(:property_definition, :enum, key: "stage", label: "Old")

      patch "/api/property_definitions/#{definition.id}", params: {
        property_definition: {label: "New", config: {options: %w[a b c]}}
      }

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["definition"]).to include("label" => "New")
      expect(body["definition"]["config"]).to include("options" => %w[a b c])
    end
  end

  describe "DELETE /api/property_definitions/:id" do
    it "soft-archives the definition" do
      sign_in user
      definition = create(:property_definition)

      delete "/api/property_definitions/#{definition.id}"

      expect(response).to have_http_status(:no_content)
      expect(definition.reload.archived).to be true
    end
  end

  describe "PATCH /api/property_definitions/reorder" do
    it "rewrites position by order of ids" do
      sign_in user
      a = create(:property_definition, key: "a", position: 1)
      b = create(:property_definition, key: "b", position: 2)
      c = create(:property_definition, key: "c", position: 3)

      patch "/api/property_definitions/reorder", params: {ids: [c.id, a.id, b.id]}

      expect(response).to have_http_status(:no_content)
      expect([a.reload.position, b.reload.position, c.reload.position]).to eq([1, 2, 0])
    end
  end
end
