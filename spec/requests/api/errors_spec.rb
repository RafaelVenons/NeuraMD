require "rails_helper"

RSpec.describe "API error shape", type: :request do
  describe "unauthenticated JSON request" do
    it "returns 401 with the standardized error envelope" do
      get api_graph_path, headers: {"ACCEPT" => "application/json"}

      expect(response).to have_http_status(:unauthorized)
      body = response.parsed_body
      expect(body).to have_key("error")
      expect(body["error"]).to include(
        "code" => "unauthorized",
        "message" => be_a(String)
      )
    end
  end

  describe "signed-in unknown route under /api" do
    let(:user) { create(:user) }
    before { sign_in user }

    it "returns 404 with the standardized error envelope" do
      get "/api/definitely-not-a-real-endpoint", headers: {"ACCEPT" => "application/json"}

      expect(response).to have_http_status(:not_found)
      body = response.parsed_body
      expect(body).to have_key("error")
      expect(body["error"]).to include("code" => "not_found")
    end
  end
end
