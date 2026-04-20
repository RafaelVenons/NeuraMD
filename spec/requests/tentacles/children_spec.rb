require "rails_helper"

RSpec.describe "Tentacle children", type: :request do
  let(:user)    { create(:user) }
  let!(:parent) { create(:note, :with_head_revision, title: "Parent Hub") }

  describe "POST /notes/:slug/tentacle/children" do
    it "redirects unauthenticated users" do
      post children_note_tentacle_path(parent.slug), params: {title: "x"}
      expect(response).to redirect_to(new_user_session_path)
    end

    context "when signed in" do
      before { sign_in user }

      it "creates a child tentacle and redirects to it" do
        expect {
          post children_note_tentacle_path(parent.slug),
            params: {title: "New Child", description: "scope"}
        }.to change(Note, :count).by(1)

        child = Note.order(:created_at).last
        expect(response).to redirect_to(note_tentacle_path(child.slug))
        expect(child.title).to eq("New Child")
        expect(child.tags.pluck(:name)).to include("tentacle")
        expect(child.head_revision.content_markdown).to include("[[Parent Hub|f:#{parent.id}]]")
      end

      it "returns JSON with tentacle_url when requested as JSON" do
        post children_note_tentacle_path(parent.slug, format: :json),
          params: {title: "JSON Child", extra_tags: "research"}.to_json,
          headers: {"Content-Type" => "application/json"}

        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body)
        expect(body["spawned"]).to be true
        expect(body["parent_slug"]).to eq(parent.slug)
        expect(body["tags"]).to include("tentacle", "research")
        expect(body["tentacle_url"]).to start_with("/notes/")
      end

      it "rejects blank title with redirect + flash" do
        post children_note_tentacle_path(parent.slug), params: {title: "   "}

        expect(response).to redirect_to(note_tentacle_path(parent.slug))
        expect(flash[:alert]).to include("title")
      end

      it "returns 404 when parent does not exist" do
        post children_note_tentacle_path("missing-slug", format: :json),
          params: {title: "Orphan"}.to_json,
          headers: {"Content-Type" => "application/json"}
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when tentacles are disabled" do
      before do
        sign_in user
        allow(Tentacles::Authorization).to receive(:enabled?).and_return(false)
      end

      it "blocks JSON with 403" do
        post children_note_tentacle_path(parent.slug, format: :json),
          params: {title: "Nope"}.to_json,
          headers: {"Content-Type" => "application/json"}
        expect(response).to have_http_status(:forbidden)
      end

      it "blocks HTML with redirect + flash" do
        post children_note_tentacle_path(parent.slug), params: {title: "Nope"}
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include("disabled")
      end
    end
  end
end
