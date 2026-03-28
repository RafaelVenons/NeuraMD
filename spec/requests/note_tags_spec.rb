require "rails_helper"

RSpec.describe "NoteTags", type: :request do
  let(:user) { create(:user) }
  let(:note) { create(:note) }
  let(:tag) { create(:tag) }
  let(:headers) { {"Content-Type" => "application/json", "Accept" => "application/json"} }

  before { sign_in user }

  describe "POST /note_tags — attach tag to note" do
    it "creates a note_tag association" do
      expect {
        post note_tags_path,
          params: {note_id: note.id, tag_id: tag.id}.to_json,
          headers: headers
      }.to change(NoteTag, :count).by(1)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["ok"]).to be(true)
    end

    it "is idempotent — does not create duplicates" do
      NoteTag.create!(note: note, tag: tag)
      expect {
        post note_tags_path,
          params: {note_id: note.id, tag_id: tag.id}.to_json,
          headers: headers
      }.not_to change(NoteTag, :count)
      expect(response).to have_http_status(:ok)
    end

    it "supports N:N — multiple tags on the same note" do
      tag2 = create(:tag)
      post note_tags_path, params: {note_id: note.id, tag_id: tag.id}.to_json, headers: headers
      post note_tags_path, params: {note_id: note.id, tag_id: tag2.id}.to_json, headers: headers
      expect(note.tags.count).to eq(2)
    end

    it "returns 404 for unknown note_id" do
      post note_tags_path,
        params: {note_id: SecureRandom.uuid, tag_id: tag.id}.to_json,
        headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for unknown tag_id" do
      post note_tags_path,
        params: {note_id: note.id, tag_id: SecureRandom.uuid}.to_json,
        headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /note_tags — detach tag from note" do
    it "removes the note_tag association" do
      NoteTag.create!(note: note, tag: tag)
      expect {
        delete note_tags_path,
          params: {note_id: note.id, tag_id: tag.id}.to_json,
          headers: headers
      }.to change(NoteTag, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end

    it "is safe when association does not exist" do
      delete note_tags_path,
        params: {note_id: note.id, tag_id: tag.id}.to_json,
        headers: headers
      expect(response).to have_http_status(:no_content)
    end

    it "allows toggling — add, remove, add again" do
      NoteTag.create!(note: note, tag: tag)

      delete note_tags_path, params: {note_id: note.id, tag_id: tag.id}.to_json, headers: headers
      expect(note.tags.count).to eq(0)

      post note_tags_path, params: {note_id: note.id, tag_id: tag.id}.to_json, headers: headers
      expect(note.tags.count).to eq(1)
    end
  end
end
