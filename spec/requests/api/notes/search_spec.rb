require "rails_helper"

RSpec.describe "API notes search", type: :request do
  let(:user) { create(:user) }

  def make_note(title, body: nil, tags: [])
    body ||= "# #{title}\n\ncontent of #{title}"
    note = create(:note, title: title)
    rev = create(:note_revision, note: note, content_markdown: body)
    note.update_columns(head_revision_id: rev.id)
    tags.each do |name|
      tag = Tag.find_or_create_by!(name: name)
      NoteTag.create!(note: note, tag: tag)
    end
    note
  end

  describe "GET /api/notes/search" do
    it "returns 401 envelope when signed out" do
      get "/api/notes/search", headers: {"ACCEPT" => "application/json"}

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to include("code" => "unauthorized")
    end

    it "returns recent notes with empty query" do
      sign_in user
      a = make_note("Alpha")
      b = make_note("Bravo")

      get "/api/notes/search", params: {q: ""}

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["results"].map { |n| n["slug"] }).to match_array([a.slug, b.slug])
      expect(body["meta"]).to include("query" => "", "has_more" => false)
    end

    it "ranks a matching title first" do
      sign_in user
      make_note("Distractor", body: "# Distractor\n\nunrelated text")
      target = make_note("Kitten photo", body: "# Kitten\n\nfluffy")

      get "/api/notes/search", params: {q: "Kitten"}

      body = response.parsed_body
      expect(body["results"].first["slug"]).to eq(target.slug)
      expect(body["results"].first).to include("title" => "Kitten photo", "snippet" => be_a(String))
    end

    it "filters by tag DSL" do
      sign_in user
      make_note("No tag")
      tagged = make_note("Tagged", tags: ["plan"])

      get "/api/notes/search", params: {q: "tag:plan"}

      body = response.parsed_body
      expect(body["results"].map { |n| n["slug"] }).to eq([tagged.slug])
    end

    it "caps limit at 25 per request" do
      sign_in user
      12.times { |i| make_note("Item #{i}") }

      get "/api/notes/search", params: {q: "", limit: 5}

      expect(response.parsed_body["results"].length).to eq(5)
      expect(response.parsed_body["meta"]).to include("limit" => 5, "has_more" => true)
    end
  end
end
