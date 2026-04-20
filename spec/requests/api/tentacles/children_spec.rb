require "rails_helper"

RSpec.describe "API tentacle children", type: :request do
  let(:user)    { create(:user) }
  let!(:parent) { create(:note, :with_head_revision, title: "Parent") }

  describe "POST /api/notes/:slug/tentacle/children" do
    it "returns 401 envelope when signed out" do
      post "/api/notes/#{parent.slug}/tentacle/children",
        params: {title: "Child"}.to_json,
        headers: {"CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json"}

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to include("code" => "unauthorized")
    end

    it "spawns a child tentacle and returns its slug + tentacle_url" do
      sign_in user

      post "/api/notes/#{parent.slug}/tentacle/children",
        params: {title: "Runner", description: "d"}.to_json,
        headers: {"CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json"}

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["parent_slug"]).to eq(parent.slug)
      expect(body["title"]).to eq("Runner")
      expect(body["slug"]).to match(/runner/)
      expect(body["tentacle_url"]).to eq("/app/notes/#{body["slug"]}/tentacle")
      expect(body["tags"]).to include("tentacle")
    end

    it "rejects blank title with unprocessable envelope" do
      sign_in user

      post "/api/notes/#{parent.slug}/tentacle/children",
        params: {title: "   "}.to_json,
        headers: {"CONTENT_TYPE" => "application/json"}

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("code" => "invalid_params")
    end

    it "returns envelope 404 when parent does not exist" do
      sign_in user

      post "/api/notes/missing/tentacle/children",
        params: {title: "x"}.to_json,
        headers: {"CONTENT_TYPE" => "application/json"}

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to include("code" => "not_found")
    end

    it "blocks with forbidden envelope when tentacles are disabled" do
      sign_in user
      allow(Tentacles::Authorization).to receive(:enabled?).and_return(false)

      post "/api/notes/#{parent.slug}/tentacle/children",
        params: {title: "x"}.to_json,
        headers: {"CONTENT_TYPE" => "application/json"}

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to include("code" => "forbidden")
    end
  end
end
