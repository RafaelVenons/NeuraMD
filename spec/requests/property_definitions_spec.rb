require "rails_helper"

RSpec.describe "Property Definitions CRUD", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /settings/properties" do
    it "renders the definitions page" do
      create(:property_definition, key: "status", value_type: "enum", label: "Status",
        config: {"options" => %w[draft review published]})

      get property_definitions_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Status")
      expect(response.body).to include("enum")
    end

    it "requires authentication" do
      sign_out user
      get property_definitions_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "POST /settings/properties" do
    it "creates a new definition" do
      post property_definitions_path, params: {
        property_definition: {key: "priority", value_type: "number", label: "Prioridade"}
      }, as: :json

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["key"]).to eq("priority")
      expect(body["value_type"]).to eq("number")
      expect(body["label"]).to eq("Prioridade")
    end

    it "creates an enum definition with options" do
      post property_definitions_path, params: {
        property_definition: {
          key: "status", value_type: "enum", label: "Status",
          config: {options: %w[draft review published]}
        }
      }, as: :json

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["config"]["options"]).to eq(%w[draft review published])
    end

    it "returns errors for invalid definition" do
      post property_definitions_path, params: {
        property_definition: {key: "", value_type: "text"}
      }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      body = response.parsed_body
      expect(body["errors"]).to be_present
    end

    it "returns errors for enum without options" do
      post property_definitions_path, params: {
        property_definition: {key: "status", value_type: "enum"}
      }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns errors for reserved key" do
      post property_definitions_path, params: {
        property_definition: {key: "title", value_type: "text"}
      }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /settings/properties/:id" do
    let!(:definition) { create(:property_definition, key: "status", value_type: "enum", label: "Status", config: {"options" => %w[draft review]}) }

    it "updates label and description" do
      patch property_definition_path(definition), params: {
        property_definition: {label: "Estado", description: "Estado da nota"}
      }, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["label"]).to eq("Estado")
      expect(body["description"]).to eq("Estado da nota")
    end

    it "updates config options" do
      patch property_definition_path(definition), params: {
        property_definition: {config: {options: %w[draft review published archived]}}
      }, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["config"]["options"]).to eq(%w[draft review published archived])
    end
  end

  describe "DELETE /settings/properties/:id" do
    let!(:definition) { create(:property_definition, key: "priority", value_type: "number") }

    it "archives the definition (soft delete)" do
      delete property_definition_path(definition), as: :json

      expect(response).to have_http_status(:no_content)
      expect(definition.reload.archived).to be true
    end
  end

  describe "PATCH /settings/properties/reorder" do
    let!(:def_a) { create(:property_definition, key: "aaa", value_type: "text", position: 0) }
    let!(:def_b) { create(:property_definition, key: "bbb", value_type: "text", position: 1) }
    let!(:def_c) { create(:property_definition, key: "ccc", value_type: "text", position: 2) }

    it "updates positions based on id order" do
      patch reorder_property_definitions_path, params: {
        ids: [def_c.id, def_a.id, def_b.id]
      }, as: :json

      expect(response).to have_http_status(:no_content)
      expect(def_c.reload.position).to eq(0)
      expect(def_a.reload.position).to eq(1)
      expect(def_b.reload.position).to eq(2)
    end
  end
end
