require "rails_helper"

RSpec.describe "API settings sub-resources", type: :request do
  let(:user) { create(:user) }

  describe "GET /api/file_imports" do
    it "returns 401 envelope when signed out" do
      get "/api/file_imports", headers: {"ACCEPT" => "application/json"}

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to include("code" => "unauthorized")
    end

    it "lists imports newest first" do
      sign_in user
      old = create(:file_import, user: user, original_filename: "old.pdf", status: "completed", created_at: 2.days.ago)
      fresh = create(:file_import, user: user, original_filename: "fresh.pdf", status: "pending")

      get "/api/file_imports"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["imports"].map { |i| i["id"] }).to eq([fresh.id, old.id])
      expect(body["imports"].first).to include(
        "original_filename" => "fresh.pdf",
        "status" => "pending",
        "base_tag" => fresh.base_tag,
        "import_tag" => fresh.import_tag
      )
    end
  end

  describe "GET /api/ai_requests" do
    it "returns 401 envelope when signed out" do
      get "/api/ai_requests", headers: {"ACCEPT" => "application/json"}

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to include("code" => "unauthorized")
    end

    it "lists requests newest first with summary fields" do
      sign_in user
      note = create(:note, title: "N")
      rev = create(:note_revision, note: note)
      note.update_columns(head_revision_id: rev.id)
      first = AiRequest.create!(
        note_revision: rev,
        capability: "rewrite",
        provider: "openai",
        status: "queued",
        max_attempts: 3
      )

      get "/api/ai_requests"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["requests"].map { |r| r["id"] }).to include(first.id)
      payload = body["requests"].find { |r| r["id"] == first.id }
      expect(payload).to include(
        "capability" => "rewrite",
        "provider" => "openai",
        "status" => "queued"
      )
      expect(payload["note"]).to include("slug" => note.slug, "title" => "N")
    end
  end

  describe "GET /api/tags with counts" do
    it "returns tags with notes_count envelope" do
      sign_in user
      plan = Tag.find_or_create_by!(name: "plan") { |t| t.color_hex = "#111111" }
      Tag.find_or_create_by!(name: "shop") { |t| t.color_hex = "#222222" }
      note = create(:note, title: "T")
      rev = create(:note_revision, note: note)
      note.update_columns(head_revision_id: rev.id)
      NoteTag.create!(note: note, tag: plan)

      get "/api/tags"

      body = response.parsed_body
      plan_payload = body["tags"].find { |t| t["name"] == "plan" }
      shop_payload = body["tags"].find { |t| t["name"] == "shop" }
      expect(plan_payload).to include("notes_count" => 1)
      expect(shop_payload).to include("notes_count" => 0)
    end
  end
end
