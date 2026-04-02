require "rails_helper"

RSpec.describe "GET /notes/search?mode=resolve", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it "returns resolved status with single matching note" do
    note = create(:note, :with_head_revision, title: "Neurociência")

    get search_notes_path, params: {q: "Neurociência", mode: "resolve"}

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["status"]).to eq("resolved")
    expect(body["match_kind"]).to eq("exact_title")
    expect(body["notes"].size).to eq(1)
    expect(body["notes"].first["id"]).to eq(note.id)
    expect(body["notes"].first["title"]).to eq("Neurociência")
    expect(body["notes"].first["slug"]).to eq(note.slug)
  end

  it "returns ambiguous status with multiple candidates" do
    note_a = create(:note, :with_head_revision, title: "Café Especial")
    note_b = create(:note, :with_head_revision, title: "Outra Nota")
    create(:note_alias, note: note_b, name: "Café Especial")

    get search_notes_path, params: {q: "Café Especial", mode: "resolve"}

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["status"]).to eq("ambiguous")
    expect(body["notes"].size).to eq(2)
    ids = body["notes"].map { |n| n["id"] }
    expect(ids).to contain_exactly(note_a.id, note_b.id)
  end

  it "returns not_found status when no match exists" do
    get search_notes_path, params: {q: "Nonexistent", mode: "resolve"}

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["status"]).to eq("not_found")
    expect(body["notes"]).to eq([])
  end

  it "requires authentication" do
    sign_out user
    get search_notes_path, params: {q: "Test", mode: "resolve"}
    expect(response).to redirect_to(new_user_session_path)
  end
end
