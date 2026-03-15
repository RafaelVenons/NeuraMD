require "rails_helper"

RSpec.describe "Graphs", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /graph" do
    it "renders the new graph page" do
      get graph_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Grafo de notas")
      expect(response.body).to include(api_graph_path)
    end
  end

  describe "GET /api/graph" do
    it "returns the normalized dataset contract" do
      tagged_note = create(:note, title: "Mapa Clinico")
      tagged_revision = create(:note_revision, note: tagged_note, content_markdown: "Resumo de cardiologia com foco clinico")
      tagged_note.update_columns(head_revision_id: tagged_revision.id)

      related_note = create(:note, title: "ECG")
      related_revision = create(:note_revision, note: related_note, content_markdown: "Interpretacao de ritmo")
      related_note.update_columns(head_revision_id: related_revision.id)

      note_tag = create(:tag, name: "importante", color_hex: "#ff6600", tag_scope: "both")
      link_tag = create(:tag, name: "relacao", color_hex: "#0099ff", tag_scope: "both")

      NoteTag.create!(note: tagged_note, tag: note_tag)
      link = create(:note_link, src_note: tagged_note, dst_note: related_note, created_in_revision: tagged_revision, hier_role: "target_is_child")
      LinkTag.create!(note_link: link, tag: link_tag)

      get api_graph_path, headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      payload = response.parsed_body

      expect(payload.keys).to contain_exactly("notes", "links", "tags", "noteTags", "linkTags", "meta")
      expect(payload["notes"].first).to include("id", "slug", "title", "excerpt", "updated_at", "created_at")
      expect(payload["links"].first).to include(
        "id" => link.id,
        "src_note_id" => tagged_note.id,
        "dst_note_id" => related_note.id,
        "hier_role" => "target_is_child"
      )
      expect(payload["tags"].map { |tag| tag["id"] }).to include(note_tag.id, link_tag.id)
      expect(payload["noteTags"]).to include({"note_id" => tagged_note.id, "tag_id" => note_tag.id})
      expect(payload["linkTags"]).to include({"note_link_id" => link.id, "tag_id" => link_tag.id})
      expect(payload["meta"]).to include(
        "note_count" => 2,
        "link_count" => 1,
        "tag_count" => 2
      )
      expect(payload["notes"].find { |note| note["id"] == tagged_note.id }["excerpt"]).to include("Resumo de cardiologia")
    end

    it "omits links pointing to notes outside the authorized active scope" do
      active_note = create(:note, title: "Ativa")
      active_revision = create(:note_revision, note: active_note, content_markdown: "Corpo ativo")
      active_note.update_columns(head_revision_id: active_revision.id)

      deleted_note = create(:note, title: "Arquivada")
      deleted_revision = create(:note_revision, note: deleted_note, content_markdown: "Corpo arquivado")
      deleted_note.update_columns(head_revision_id: deleted_revision.id)

      create(:note_link, src_note: active_note, dst_note: deleted_note, created_in_revision: active_revision)
      deleted_note.soft_delete!

      get api_graph_path, headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["notes"].map { |item| item["id"] }).to eq([active_note.id])
      expect(response.parsed_body["links"]).to eq([])
    end
  end
end
