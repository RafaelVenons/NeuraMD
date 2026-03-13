require "rails_helper"

RSpec.describe "LinkTags", type: :request do
  let(:user) { create(:user) }
  let(:note) { create(:note) }
  let(:dst)  { create(:note) }
  let(:link) { create(:note_link, src_note: note, dst_note: dst) }
  let(:headers) { {"Content-Type" => "application/json", "Accept" => "application/json"} }

  before { sign_in user }

  describe "POST /link_tags — add tag to link" do
    it "creates a link_tag association" do
      tag = create(:tag)
      expect {
        post link_tags_path,
          params: {note_link_id: link.id, tag_id: tag.id}.to_json,
          headers: headers
      }.to change(LinkTag, :count).by(1)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["ok"]).to be(true)
    end

    it "is idempotent — does not create duplicates" do
      tag = create(:tag)
      LinkTag.create!(note_link: link, tag: tag)
      expect {
        post link_tags_path,
          params: {note_link_id: link.id, tag_id: tag.id}.to_json,
          headers: headers
      }.not_to change(LinkTag, :count)
      expect(response).to have_http_status(:ok)
    end

    it "supports N:N — multiple tags on the same link" do
      tag1 = create(:tag)
      tag2 = create(:tag)
      post link_tags_path, params: {note_link_id: link.id, tag_id: tag1.id}.to_json, headers: headers
      post link_tags_path, params: {note_link_id: link.id, tag_id: tag2.id}.to_json, headers: headers
      expect(link.tags.count).to eq(2)
    end

    it "returns 404 for unknown note_link_id" do
      tag = create(:tag)
      post link_tags_path,
        params: {note_link_id: SecureRandom.uuid, tag_id: tag.id}.to_json,
        headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /link_tags — remove tag from link" do
    it "removes the link_tag association" do
      tag = create(:tag)
      LinkTag.create!(note_link: link, tag: tag)
      expect {
        delete link_tags_path,
          params: {note_link_id: link.id, tag_id: tag.id}.to_json,
          headers: headers
      }.to change(LinkTag, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end

    it "is safe when association does not exist (no error)" do
      tag = create(:tag)
      delete link_tags_path,
        params: {note_link_id: link.id, tag_id: tag.id}.to_json,
        headers: headers
      expect(response).to have_http_status(:no_content)
    end

    it "allows toggling — add, remove, add again independently" do
      tag = create(:tag)
      LinkTag.create!(note_link: link, tag: tag)

      delete link_tags_path, params: {note_link_id: link.id, tag_id: tag.id}.to_json, headers: headers
      expect(link.tags.count).to eq(0)

      post link_tags_path, params: {note_link_id: link.id, tag_id: tag.id}.to_json, headers: headers
      expect(link.tags.count).to eq(1)
    end
  end
end
