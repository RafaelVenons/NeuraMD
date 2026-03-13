require "rails_helper"

RSpec.describe "Tags", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /tags" do
    it "returns JSON list of tags" do
      create(:tag, name: "urgent", color_hex: "#ef4444")
      get tags_path, headers: {"Accept" => "application/json"}
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json).to be_an(Array)
      expect(json.first).to include("id", "name", "color_hex", "tag_scope")
    end

    it "returns all tags ordered by name" do
      create(:tag, name: "zebra")
      create(:tag, name: "alpha")
      get tags_path, headers: {"Accept" => "application/json"}
      names = response.parsed_body.map { |t| t["name"] }
      expect(names).to eq(names.sort)
    end
  end

  describe "POST /tags" do
    let(:headers) { {"Content-Type" => "application/json", "Accept" => "application/json"} }

    it "creates a tag and returns 201" do
      expect {
        post tags_path,
          params: {tag: {name: "importância", color_hex: "#f59e0b", tag_scope: "both"}}.to_json,
          headers: headers
      }.to change(Tag, :count).by(1)

      expect(response).to have_http_status(:created)
      json = response.parsed_body
      expect(json["name"]).to eq("importância")
      expect(json["color_hex"]).to eq("#f59e0b")
    end

    it "returns unprocessable_entity for duplicate name" do
      create(:tag, name: "dup")
      post tags_path,
        params: {tag: {name: "dup"}}.to_json,
        headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /tags/:id" do
    it "destroys the tag" do
      tag = create(:tag)
      expect {
        delete tag_path(tag), headers: {"Accept" => "application/json"}
      }.to change(Tag, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end
  end
end
