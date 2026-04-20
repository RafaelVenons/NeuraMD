require "rails_helper"

RSpec.describe "API note links", type: :request do
  let(:user) { create(:user) }

  def make_note(title, body = nil)
    body ||= "# #{title}\n\nbody"
    create(:note, title: title).tap do |n|
      rev = create(:note_revision, note: n, content_markdown: body)
      n.update_columns(head_revision_id: rev.id)
    end
  end

  describe "GET /api/notes/:slug/links" do
    it "returns 401 envelope when signed out" do
      note = make_note("Solo")
      get "/api/notes/#{note.slug}/links", headers: {"ACCEPT" => "application/json"}

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to include("code" => "unauthorized")
    end

    it "returns empty arrays for a note with no links" do
      sign_in user
      note = make_note("Solo")

      get "/api/notes/#{note.slug}/links"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["outgoing"]).to eq([])
      expect(body["incoming"]).to eq([])
    end

    it "lists active outgoing and incoming links with note summaries" do
      sign_in user
      parent = make_note("Parent")
      child  = make_note("Child")
      peer   = make_note("Peer")

      rev = parent.head_revision
      NoteLink.create!(src_note: parent, dst_note: child, hier_role: "target_is_child", created_in_revision: rev)
      NoteLink.create!(src_note: peer,   dst_note: parent, hier_role: nil, created_in_revision: peer.head_revision)

      get "/api/notes/#{parent.slug}/links"

      body = response.parsed_body
      expect(body["outgoing"].map { |l| l["slug"] }).to eq([child.slug])
      expect(body["outgoing"].first).to include("title" => "Child", "hier_role" => "target_is_child")
      expect(body["incoming"].map { |l| l["slug"] }).to eq([peer.slug])
      expect(body["incoming"].first).to include("title" => "Peer", "hier_role" => nil)
    end

    it "returns envelope 404 when slug is unknown" do
      sign_in user
      get "/api/notes/missing/links"

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to include("code" => "not_found")
    end
  end
end
