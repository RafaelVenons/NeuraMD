require "rails_helper"

RSpec.describe "Aliases API", type: :request do
  let(:user) { create(:user) }
  let(:note) { create(:note, :with_head_revision) }

  before { sign_in user }

  describe "PATCH /notes/:slug/aliases" do
    it "sets aliases and returns them" do
      patch aliases_note_path(note.slug), params: {aliases: ["Cardio", "Heart"]}, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["aliases"]).to contain_exactly("Cardio", "Heart")
    end

    it "replaces existing aliases" do
      create(:note_alias, note: note, name: "Old")

      patch aliases_note_path(note.slug), params: {aliases: ["New"]}, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["aliases"]).to eq(["New"])
      expect(note.note_aliases.reload.count).to eq(1)
    end

    it "clears aliases with empty array" do
      create(:note_alias, note: note, name: "Old")

      patch aliases_note_path(note.slug), params: {aliases: []}, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["aliases"]).to be_empty
    end

    it "returns 422 when alias collides with another note" do
      other = create(:note, :with_head_revision)
      create(:note_alias, note: other, name: "Taken")

      patch aliases_note_path(note.slug), params: {aliases: ["Taken"]}, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to be_present
    end

    it "requires authentication" do
      sign_out user
      patch aliases_note_path(note.slug), params: {aliases: ["Test"]}, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
