require "rails_helper"

RSpec.describe "Tentacle inbox", type: :request do
  let(:user)   { create(:user) }
  let!(:owner) { create(:note, :with_head_revision, title: "Owner") }
  let!(:other) { create(:note, :with_head_revision, title: "Other") }

  def send_msg(to: owner, from: other, content: "hi", delivered: false)
    attrs = {from_note: from, to_note: to, content: content}
    attrs[:delivered_at] = 1.minute.ago if delivered
    AgentMessage.create!(attrs)
  end

  describe "GET /notes/:slug/tentacle/inbox" do
    it "returns 401 for unauthenticated requests" do
      get inbox_note_tentacle_path(owner.slug, format: :json)
      expect(response).to have_http_status(:unauthorized)
    end

    context "when signed in" do
      before { sign_in user }

      it "returns messages newest first as JSON" do
        older = send_msg(content: "first")
        older.update!(created_at: 2.hours.ago)
        newer = send_msg(content: "second")

        get inbox_note_tentacle_path(owner.slug, format: :json)

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["count"]).to eq(2)
        expect(body["messages"].map { |m| m["id"] }).to eq([newer.id, older.id])
        expect(body["pending_count"]).to eq(2)
      end

      it "filters to pending when only_pending=true" do
        delivered = send_msg(content: "old", delivered: true)
        pending   = send_msg(content: "new")

        get inbox_note_tentacle_path(owner.slug, format: :json, only_pending: true)

        body = JSON.parse(response.body)
        ids = body["messages"].map { |m| m["id"] }
        expect(ids).to include(pending.id)
        expect(ids).not_to include(delivered.id)
      end

      it "returns 404 when note does not exist" do
        get inbox_note_tentacle_path("missing-slug", format: :json)
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /notes/:slug/tentacle/inbox/deliver_all" do
    context "when signed in" do
      before { sign_in user }

      it "flips pending messages and reports the count" do
        pending = send_msg
        already = send_msg(delivered: true)

        post inbox_deliver_all_note_tentacle_path(owner.slug, format: :json)

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["marked_delivered"]).to eq(1)
        expect(pending.reload).to be_delivered
        expect(already.reload.delivered_at).to be_present
      end
    end
  end

  describe "when tentacles are disabled" do
    before do
      sign_in user
      allow(Tentacles::Authorization).to receive(:enabled?).and_return(false)
    end

    it "blocks GET with 403" do
      get inbox_note_tentacle_path(owner.slug, format: :json)
      expect(response).to have_http_status(:forbidden)
    end

    it "blocks POST deliver_all with 403" do
      post inbox_deliver_all_note_tentacle_path(owner.slug, format: :json)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
