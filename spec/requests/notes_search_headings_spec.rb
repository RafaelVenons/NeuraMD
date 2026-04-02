require "rails_helper"

RSpec.describe "Notes search mode=headings", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  let(:note) { create(:note, :with_head_revision) }

  def create_headings!(note, content)
    Headings::SyncService.call(note:, content:)
  end

  it "returns headings for a note ordered by position" do
    create_headings!(note, "# Title\n## Section A\n### Sub")

    get search_notes_path(mode: "headings", note_id: note.id), as: :json

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body.size).to eq(3)
    expect(body.map { |h| h["text"] }).to eq(["Title", "Section A", "Sub"])
    expect(body.map { |h| h["slug"] }).to eq(["title", "section-a", "sub"])
    expect(body.map { |h| h["level"] }).to eq([1, 2, 3])
    expect(body.map { |h| h["position"] }).to eq([0, 1, 2])
  end

  it "filters headings by text query" do
    create_headings!(note, "# Introduction\n## Methods\n## Results")

    get search_notes_path(mode: "headings", note_id: note.id, q: "meth"), as: :json

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body.size).to eq(1)
    expect(body.first["text"]).to eq("Methods")
  end

  it "returns empty array for note with no headings" do
    get search_notes_path(mode: "headings", note_id: note.id), as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq([])
  end

  it "requires authentication" do
    sign_out user
    get search_notes_path(mode: "headings", note_id: note.id), as: :json

    expect(response.status).to be_in([302, 401])
  end

  it "returns 404 for non-existent note_id" do
    get search_notes_path(mode: "headings", note_id: "00000000-0000-0000-0000-000000000000"), as: :json

    expect(response).to have_http_status(:not_found)
  end
end
