require "rails_helper"

RSpec.describe "Tentacles dashboard", type: :request do
  let(:user) { create(:user) }
  let!(:note) do
    create(:note, title: "Dashboard Playground").tap do |n|
      rev = create(:note_revision, note: n, content_markdown: "body")
      n.update_columns(head_revision_id: rev.id)
    end
  end
  let!(:other_note) do
    create(:note, title: "Other Note").tap do |n|
      rev = create(:note_revision, note: n, content_markdown: "body")
      n.update_columns(head_revision_id: rev.id)
    end
  end

  describe "GET /tentacles" do
    it "redirects unauthenticated users" do
      get tentacles_dashboard_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "renders empty state when no sessions are running" do
      sign_in user
      get tentacles_dashboard_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nenhum tentáculo rodando")
    end

    it "lists active sessions joined to their notes" do
      sign_in user
      fake_session = instance_double(
        TentacleRuntime::Session,
        pid: 4242,
        alive?: true,
        started_at: 2.minutes.ago
      )
      allow(fake_session).to receive(:instance_variable_get).with(:@command).and_return(["bash", "-l"])
      TentacleRuntime::SESSIONS[note.id] = fake_session

      get tentacles_dashboard_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Dashboard Playground")
      expect(response.body).to include("bash -l")
      expect(response.body).not_to include("Other Note")
    ensure
      TentacleRuntime::SESSIONS.delete(note.id)
    end

    it "blocks access when tentacles are disabled" do
      sign_in user
      allow(Tentacles::Authorization).to receive(:enabled?).and_return(false)

      get tentacles_dashboard_path

      expect(response).to redirect_to(root_path)
    end
  end

  describe "GET /tentacles/multi" do
    before { sign_in user }

    it "redirects to the dashboard when no ids are supplied" do
      get tentacles_multi_path
      expect(response).to redirect_to(tentacles_dashboard_path)
    end

    it "redirects when no ids match a real note" do
      get tentacles_multi_path, params: { ids: [SecureRandom.uuid] }
      expect(response).to redirect_to(tentacles_dashboard_path)
    end

    it "renders a panel per valid id and wires the Stimulus controller" do
      get tentacles_multi_path, params: { ids: [note.id, other_note.id] }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Dashboard Playground")
      expect(response.body).to include("Other Note")
      expect(response.body.scan("data-controller=\"tentacle\"").size).to eq(2)
    end

    it "accepts ids as a comma-separated string" do
      get tentacles_multi_path, params: { ids: "#{note.id},#{other_note.id}" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Dashboard Playground")
      expect(response.body).to include("Other Note")
    end

    it "blocks access when tentacles are disabled" do
      allow(Tentacles::Authorization).to receive(:enabled?).and_return(false)

      get tentacles_multi_path, params: { ids: [note.id] }

      expect(response).to redirect_to(root_path)
    end
  end
end
