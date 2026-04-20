require "rails_helper"

RSpec.describe "API tentacle inbox", type: :request do
  let(:user)   { create(:user) }
  let!(:owner) { create(:note, :with_head_revision, title: "Owner") }
  let!(:other) { create(:note, :with_head_revision, title: "Other") }

  def send_msg(to: owner, from: other, content: "hi", delivered: false)
    attrs = {from_note: from, to_note: to, content: content}
    attrs[:delivered_at] = 1.minute.ago if delivered
    AgentMessage.create!(attrs)
  end

  describe "GET /api/notes/:slug/tentacle/inbox" do
    it "returns 401 in the shared envelope when signed out" do
      get "/api/notes/#{owner.slug}/tentacle/inbox", headers: {"ACCEPT" => "application/json"}

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to include("code" => "unauthorized")
    end

    it "returns messages newest-first with pending count" do
      sign_in user
      older = send_msg(content: "first")
      older.update!(created_at: 2.hours.ago)
      newer = send_msg(content: "second")

      get "/api/notes/#{owner.slug}/tentacle/inbox"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["count"]).to eq(2)
      expect(body["pending_count"]).to eq(2)
      expect(body["messages"].map { |m| m["id"] }).to eq([newer.id, older.id])
      expect(body["messages"].first).to include("from_slug" => other.slug, "content" => "second", "delivered" => false)
    end

    it "filters to pending when only_pending=true" do
      sign_in user
      send_msg(content: "old", delivered: true)
      pending = send_msg(content: "new")

      get "/api/notes/#{owner.slug}/tentacle/inbox", params: {only_pending: true}

      body = response.parsed_body
      expect(body["messages"].map { |m| m["id"] }).to eq([pending.id])
    end

    it "returns the envelope 404 when the slug is unknown" do
      sign_in user
      get "/api/notes/missing/tentacle/inbox"

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to include("code" => "not_found")
    end

    it "blocks with forbidden envelope when tentacles are disabled" do
      sign_in user
      allow(Tentacles::Authorization).to receive(:enabled?).and_return(false)

      get "/api/notes/#{owner.slug}/tentacle/inbox"

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to include("code" => "forbidden")
    end
  end

  describe "POST /api/notes/:slug/tentacle/inbox/deliver" do
    before { sign_in user }

    it "flips only the listed ids and reports the count" do
      flip = send_msg
      keep = send_msg

      post "/api/notes/#{owner.slug}/tentacle/inbox/deliver",
        params: {ids: [flip.id]}.to_json,
        headers: {"CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json"}

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({"slug" => owner.slug, "marked_delivered" => 1})
      expect(flip.reload).to be_delivered
      expect(keep.reload).not_to be_delivered
    end

    it "returns 0 when ids is blank" do
      send_msg
      post "/api/notes/#{owner.slug}/tentacle/inbox/deliver",
        params: {ids: []}.to_json,
        headers: {"CONTENT_TYPE" => "application/json"}

      expect(response.parsed_body["marked_delivered"]).to eq(0)
    end
  end
end
