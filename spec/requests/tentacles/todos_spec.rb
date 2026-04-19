require "rails_helper"

RSpec.describe "Tentacle todos", type: :request do
  let(:user) { create(:user) }
  let!(:note) do
    create(:note, title: "Tentacle Todos").tap do |n|
      rev = create(:note_revision, note: n, content_markdown: initial_body)
      n.update_columns(head_revision_id: rev.id)
    end
  end
  let(:initial_body) { "Intro\n\n## Todos\n\n- [ ] first\n- [x] second\n" }

  describe "GET /notes/:slug/tentacle/todos" do
    it "redirects unauthenticated users" do
      get todos_note_tentacle_path(note.slug)
      expect(response).to redirect_to(new_user_session_path)
    end

    it "returns the current todos as JSON" do
      sign_in user
      get todos_note_tentacle_path(note.slug, format: :json)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["todos"]).to eq([
        { "text" => "first", "done" => false },
        { "text" => "second", "done" => true }
      ])
    end
  end

  describe "PATCH /notes/:slug/tentacle/todos" do
    before { sign_in user }

    it "updates todos and returns the normalized list" do
      patch todos_note_tentacle_path(note.slug, format: :json),
        params: { todos: [{ text: "updated", done: true }, { text: "new" }] }.to_json,
        headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["todos"]).to eq([
        { "text" => "updated", "done" => true },
        { "text" => "new", "done" => false }
      ])

      note.reload
      expect(note.head_revision.content_markdown).to include("Intro")
      expect(note.head_revision.content_markdown).to include("- [x] updated")
      expect(note.head_revision.content_markdown).to include("- [ ] new")
      expect(note.head_revision.content_markdown).not_to include("- [ ] first")
    end

    it "rejects missing todos param with 400" do
      patch todos_note_tentacle_path(note.slug, format: :json),
        params: {}.to_json,
        headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "when tentacles are disabled" do
    before do
      sign_in user
      allow(Tentacles::Authorization).to receive(:enabled?).and_return(false)
    end

    it "blocks GET with 403" do
      get todos_note_tentacle_path(note.slug, format: :json)
      expect(response).to have_http_status(:forbidden)
    end

    it "blocks PATCH with 403" do
      patch todos_note_tentacle_path(note.slug, format: :json),
        params: { todos: [{ text: "x" }] }.to_json,
        headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:forbidden)
    end
  end
end
