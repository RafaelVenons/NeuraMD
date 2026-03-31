require "rails_helper"

RSpec.describe "Properties API", type: :request do
  let(:user) { create(:user) }
  let(:note) { create(:note, :with_head_revision) }

  before do
    sign_in user
    create(:property_definition, key: "status", value_type: "enum", config: {"options" => %w[draft review published]})
    create(:property_definition, key: "priority", value_type: "number")
    create(:property_definition, key: "due_date", value_type: "date")
  end

  describe "PATCH /notes/:slug/properties" do
    it "sets a property and returns updated state" do
      patch properties_note_path(note.slug), params: {changes: {status: "draft"}}, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["properties"]["status"]).to eq("draft")
      expect(body["properties_errors"]).to eq({})
    end

    it "sets multiple properties at once" do
      patch properties_note_path(note.slug), params: {changes: {status: "review", priority: 5}}, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["properties"]["status"]).to eq("review")
      expect(body["properties"]["priority"]).to eq(5)
    end

    it "removes a property with null value" do
      Properties::SetService.call(note: note, changes: {"status" => "draft"}, author: user)
      note.reload

      patch properties_note_path(note.slug), params: {changes: {status: nil}}, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["properties"]).not_to have_key("status")
    end

    it "stores invalid values in lenient mode and returns errors" do
      patch properties_note_path(note.slug), params: {changes: {status: "invalid_option"}}, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["properties"]["status"]).to eq("invalid_option")
      expect(body["properties_errors"]["status"]).to be_present
    end

    it "returns 422 for unknown property keys" do
      patch properties_note_path(note.slug), params: {changes: {unknown_key: "value"}}, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      body = response.parsed_body
      expect(body["error"]).to include("unknown_key")
    end

    it "requires authentication" do
      sign_out user
      patch properties_note_path(note.slug), params: {changes: {status: "draft"}}, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
