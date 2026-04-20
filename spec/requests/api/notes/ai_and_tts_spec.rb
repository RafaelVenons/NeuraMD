require "rails_helper"

RSpec.describe "API note AI + TTS sidebars", type: :request do
  let(:user) { create(:user) }

  def make_note(title = "N")
    note = create(:note, title: title)
    rev = create(:note_revision, note: note)
    note.update_columns(head_revision_id: rev.id)
    [note, rev]
  end

  describe "GET /api/notes/:slug/ai_requests" do
    it "returns 401 envelope when signed out" do
      note, _rev = make_note
      get "/api/notes/#{note.slug}/ai_requests", headers: {"ACCEPT" => "application/json"}

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to include("code" => "unauthorized")
    end

    it "lists recent requests scoped to the note" do
      sign_in user
      note, rev = make_note
      other, other_rev = make_note("Other")
      mine = AiRequest.create!(note_revision: rev, capability: "rewrite", provider: "openai", status: "queued", max_attempts: 3)
      AiRequest.create!(note_revision: other_rev, capability: "rewrite", provider: "openai", status: "queued", max_attempts: 3)

      get "/api/notes/#{note.slug}/ai_requests"

      body = response.parsed_body
      expect(body["requests"].map { |r| r["id"] }).to eq([mine.id])
      expect(body["requests"].first).to include("capability" => "rewrite", "status" => "queued")
      expect(other).to be_persisted
    end

    it "returns 404 envelope for missing note" do
      sign_in user
      get "/api/notes/missing/ai_requests"
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to include("code" => "not_found")
    end
  end

  describe "GET /api/notes/:slug/tts" do
    it "returns 401 envelope when signed out" do
      note, _rev = make_note
      get "/api/notes/#{note.slug}/tts", headers: {"ACCEPT" => "application/json"}
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns empty payload when no TTS asset exists" do
      sign_in user
      note, _rev = make_note

      get "/api/notes/#{note.slug}/tts"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["active_asset"]).to be_nil
      expect(body["library_count"]).to eq(0)
    end
  end
end
