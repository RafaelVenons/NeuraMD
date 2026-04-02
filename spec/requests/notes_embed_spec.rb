# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Notes embed endpoint", type: :request do
  let(:user) { create(:user) }

  let(:markdown) do
    <<~MD
      # Introduction

      Intro text.

      ## Details

      Detail paragraph.

      ## Conclusion

      Final thoughts.

      Key insight here. ^key-insight
    MD
  end

  let(:note) do
    n = create(:note)
    rev = create(:note_revision, note: n, content_markdown: markdown)
    n.update_columns(head_revision_id: rev.id)
    n
  end

  before { sign_in user }

  describe "GET /notes/:slug/embed" do
    it "returns markdown content for a heading embed" do
      get embed_note_path(note.slug, heading: "details"), headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      data = response.parsed_body
      expect(data["found"]).to be true
      expect(data["markdown"]).to include("## Details")
      expect(data["markdown"]).to include("Detail paragraph.")
      expect(data["markdown"]).not_to include("## Conclusion")
      expect(data["note_title"]).to eq(note.title)
      expect(data["note_slug"]).to eq(note.slug)
    end

    it "returns markdown content for a block embed" do
      get embed_note_path(note.slug, block: "key-insight"), headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      data = response.parsed_body
      expect(data["found"]).to be true
      expect(data["markdown"]).to include("Key insight here.")
      expect(data["markdown"]).not_to include("^key-insight")
    end

    it "returns 404 when note does not exist" do
      get embed_note_path("nonexistent-note", heading: "intro"), headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 when heading is not found" do
      get embed_note_path(note.slug, heading: "nonexistent"), headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:not_found)
      data = response.parsed_body
      expect(data["found"]).to be false
    end

    it "returns 404 when block is not found" do
      get embed_note_path(note.slug, block: "nonexistent"), headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:not_found)
      data = response.parsed_body
      expect(data["found"]).to be false
    end

    it "returns 404 for deleted note" do
      note.soft_delete!

      get embed_note_path(note.slug, heading: "details"), headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for note without revisions" do
      bare_note = create(:note)

      get embed_note_path(bare_note.slug, heading: "intro"), headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      sign_out user

      get embed_note_path(note.slug, heading: "details"), headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:unauthorized).or have_http_status(:redirect)
    end
  end
end
