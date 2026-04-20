require "rails_helper"

RSpec.describe "API notes", type: :request do
  let(:user) { create(:user) }

  def build_note(title:, body: "# Body\n\nSome content.", tags: [])
    create(:note, title: title).tap do |n|
      rev = create(:note_revision, note: n, content_markdown: body)
      n.update_columns(head_revision_id: rev.id)
      tags.each do |tag_name|
        tag = Tag.find_or_create_by!(name: tag_name)
        NoteTag.find_or_create_by!(note: n, tag: tag)
      end
    end
  end

  describe "GET /api/notes/:slug" do
    it "returns 401 in the shared envelope when signed out" do
      note = build_note(title: "Anon")

      get "/api/notes/#{note.slug}", headers: {"ACCEPT" => "application/json"}

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to include("code" => "unauthorized")
    end

    it "returns the note, head revision content and metadata" do
      sign_in user
      note = build_note(title: "My Note", body: "# Heading\n\nBody.", tags: ["plan", "plan-estrutura"])
      note.note_aliases.create!(name: "my-alias")

      get "/api/notes/#{note.slug}"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["note"]).to include("id" => note.id, "slug" => note.slug, "title" => "My Note")
      expect(body["revision"]["content_markdown"]).to eq("# Heading\n\nBody.")
      expect(body["tags"]).to contain_exactly(
        a_hash_including("name" => "plan"),
        a_hash_including("name" => "plan-estrutura")
      )
      expect(body["aliases"]).to contain_exactly("my-alias")
      expect(body["properties"]).to eq({})
    end

    it "returns a standardized 404 envelope for unknown slugs" do
      sign_in user
      get "/api/notes/does-not-exist"

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to include("code" => "not_found")
    end

    it "resolves slug redirects by pointing at the canonical slug" do
      sign_in user
      note = build_note(title: "Renamed")
      SlugRedirect.create!(note: note, slug: "old-slug")

      get "/api/notes/old-slug"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["note"]["slug"]).to eq(note.slug)
    end
  end
end
