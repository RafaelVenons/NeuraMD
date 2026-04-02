require "rails_helper"

RSpec.describe "Notes search mode=blocks", type: :request do
  let(:user) { create(:user) }
  let(:note) { create(:note, :with_head_revision) }

  before { sign_in user }

  it "returns blocks for a note ordered by position" do
    create(:note_block, note: note, block_id: "b1", content: "First block", block_type: "paragraph", position: 0)
    create(:note_block, note: note, block_id: "b2", content: "Second block", block_type: "list_item", position: 1)

    get search_notes_path(mode: "blocks", note_id: note.id), headers: {"Accept" => "application/json"}

    expect(response).to have_http_status(:ok)
    data = response.parsed_body
    expect(data.length).to eq(2)
    expect(data.first["block_id"]).to eq("b1")
    expect(data.last["block_id"]).to eq("b2")
    expect(data.first["block_type"]).to eq("paragraph")
  end

  it "filters blocks by text query" do
    create(:note_block, note: note, block_id: "b1", content: "First paragraph", position: 0)
    create(:note_block, note: note, block_id: "b2", content: "Second item", position: 1)

    get search_notes_path(mode: "blocks", note_id: note.id, q: "paragraph"), headers: {"Accept" => "application/json"}

    data = response.parsed_body
    expect(data.length).to eq(1)
    expect(data.first["block_id"]).to eq("b1")
  end

  it "returns empty array for note with no blocks" do
    get search_notes_path(mode: "blocks", note_id: note.id), headers: {"Accept" => "application/json"}

    expect(response.parsed_body).to eq([])
  end
end
