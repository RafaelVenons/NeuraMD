require "rails_helper"
require "securerandom"

RSpec.describe "Notes", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /notes" do
    it "redirects to the graph page" do
      create(:note, :with_head_revision)
      get notes_path
      expect(response).to redirect_to(graph_path)
    end

    it "redirects even when query params are present" do
      active = create(:note, title: "Active")
      deleted = create(:note, title: "Deleted", deleted_at: Time.current)
      get notes_path, params: { q: "arritmia" }
      expect(response).to redirect_to(graph_path)
    end
  end

  describe "GET /notes/new" do
    it "returns http success" do
      get new_note_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /notes" do
    let(:valid_params) { {note: {title: "Minha Nota", detected_language: "pt-BR"}} }

    it "creates a note and redirects" do
      expect {
        post notes_path, params: valid_params
      }.to change(Note, :count).by(1)

      expect(response).to have_http_status(:redirect)
      note = Note.order(created_at: :desc).find_by!(title: "Minha Nota")
      expect(note.title).to eq("Minha Nota")
      follow_redirect!
      expect(response).to have_http_status(:ok)
    end

    it "renders new on invalid params" do
      post notes_path, params: {note: {title: ""}}
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /notes/:slug" do
    let(:note) { create(:note, :with_head_revision) }

    it "returns http success" do
      get note_path(note.slug)
      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for deleted note" do
      note.soft_delete!
      get note_path(note.slug)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /notes/search" do
    let(:suffix) { SecureRandom.hex(4) }
    let!(:exactish) { create(:note, title: "Cardio Geral #{suffix}") }
    let!(:fuzzy) { create(:note, title: "Cardiologia Avancada #{suffix}") }
    let!(:other) { create(:note, title: "Neurologia") }

    it "returns title matches ordered by relevance" do
      get search_notes_path, params: { q: "cardio" }

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body.map { |note| note["id"] }
      expect(ids).to include(exactish.id, fuzzy.id)
      expect(ids.index(exactish.id)).to be < ids.index(fuzzy.id)
      expect(response.parsed_body.map { |note| note["title"] }).not_to include("Neurologia")
    end

    it "excludes the current note from search results when requested" do
      get search_notes_path, params: { q: "cardio", exclude_id: exactish.id }

      expect(response).to have_http_status(:ok)
      titles = response.parsed_body.map { |note| note["title"] }.uniq
      expect(titles).not_to include("Cardio Geral #{suffix}")
    end

    it "returns finder results with content snippets" do
      content_match = create(:note, title: "Neurologia")
      content_revision = create(:note_revision, note: content_match, content_markdown: "Paciente com arritmia recorrente em acompanhamento")
      content_match.update_columns(head_revision_id: content_revision.id)

      get search_notes_path, params: { q: "arritmia", mode: "finder", limit: 5 }

      expect(response).to have_http_status(:ok)
      payload = response.parsed_body
      expect(payload["results"].first["title"]).to eq("Neurologia")
      expect(payload["results"].first["snippet"]).to include("arritmia")
      expect(payload["meta"]["limit"]).to eq(5)
    end

    it "strips wikilink UUIDs from finder snippets" do
      linked = create(:note, title: "Resumo limpo")
      target = create(:note, title: "Destino")
      revision = create(:note_revision, note: linked, content_markdown: "[[Destino|#{target.id}]] em acompanhamento")
      linked.update_columns(head_revision_id: revision.id)

      get search_notes_path, params: { q: "Destino", mode: "finder", limit: 5 }

      expect(response).to have_http_status(:ok)
      snippet = response.parsed_body["results"].find { |result| result["title"] == "Resumo limpo" }["snippet"]
      expect(snippet).to include("Destino")
      expect(snippet).not_to include(target.id)
    end

    it "strips normalized UUIDs from finder snippets" do
      linked = create(:note, title: "Resumo sem uuid")
      revision = create(:note_revision, note: linked, content_markdown: "Texto inicial")
      revision.update_columns(
        content_plain: "Minha primeira nota f:6676ab19 f3d8 4cef bbbe 31679f1f8423 e v:3aa6e5f1 c0e1 4ddf 801a 4589c335979a limpo"
      )
      linked.update_columns(head_revision_id: revision.id)

      get search_notes_path, params: { q: "limpo", mode: "finder", limit: 5 }

      expect(response).to have_http_status(:ok)
      snippet = response.parsed_body["results"].find { |result| result["title"] == "Resumo sem uuid" }["snippet"]
      expect(snippet).to eq("Minha primeira nota e limpo")
    end

    it "rejects invalid finder regex" do
      get search_notes_path, params: { q: "[abc", mode: "finder", regex: "1" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("Regex invalida")
    end
  end

  describe "GET /notes/:slug/edit" do
    let(:note) { create(:note) }

    it "returns http success" do
      get edit_note_path(note.slug)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /notes/:slug" do
    let(:note) { create(:note) }

    it "updates the note" do
      patch note_path(note.slug), params: {note: {title: "Novo Título"}}
      expect(response).to have_http_status(:redirect)
      expect(note.reload.title).to eq("Novo Título")
    end

    it "renders edit on invalid params" do
      patch note_path(note.slug), params: {note: {title: ""}}
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /notes/:slug" do
    let(:note) { create(:note) }

    it "soft deletes the note" do
      delete note_path(note.slug)
      expect(response).to have_http_status(:redirect)
      expect(note.reload.deleted?).to be(true)
    end
  end

  # Three-layer save strategy:
  # localStorage (3s) → crash protection only, no server request
  # draft (60s)       → server-side upsert, 1 per note, no history
  # checkpoint        → manual save, permanent, appears in history

  describe "POST /notes/:slug/draft (layer 2 — server draft)" do
    let!(:note) { create(:note) }
    let(:headers) { {"Content-Type" => "application/json", "Accept" => "application/json"} }
    let(:conteudo) { "# Título\n\n" + ("Parágrafo de conteúdo longo. " * 15) }

    it "creates a draft revision and returns saved: true" do
      expect {
        post draft_note_path(note.slug),
          params: {content_markdown: conteudo}.to_json,
          headers: headers
      }.to change(NoteRevision, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["saved"]).to be(true)
      expect(response.parsed_body["kind"]).to eq("draft")
    end

    it "replaces previous draft (upsert — only one draft per note)" do
      post draft_note_path(note.slug),
        params: {content_markdown: "primeiro draft"}.to_json,
        headers: headers

      expect {
        post draft_note_path(note.slug),
          params: {content_markdown: "segundo draft"}.to_json,
          headers: headers
      }.not_to change(NoteRevision, :count)

      expect(note.note_revisions.where(revision_kind: :draft).count).to eq(1)
    end

    it "nota sem revisão abre editor com conteúdo vazio (não levanta erro)" do
      get note_path(note.slug)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /notes/:slug/checkpoint (layer 3 — manual save)" do
    let!(:note) { create(:note, :with_head_revision) }
    let(:headers) { {"Content-Type" => "application/json", "Accept" => "application/json"} }

    it "creates a permanent checkpoint revision" do
      expect {
        post checkpoint_note_path(note.slug),
          params: {content_markdown: "# Checkpoint\n\n" + ("conteúdo. " * 30)}.to_json,
          headers: headers
      }.to change { note.note_revisions.where(revision_kind: :checkpoint).count }.by(1)

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["saved"]).to be(true)
      expect(json["kind"]).to eq("checkpoint")
      expect(json["revision_id"]).to be_present
    end

    it "deletes existing draft when checkpoint is saved" do
      post draft_note_path(note.slug),
        params: {content_markdown: "draft antes do checkpoint"}.to_json,
        headers: headers

      post checkpoint_note_path(note.slug),
        params: {content_markdown: "# Final\n\n" + ("conteúdo. " * 30)}.to_json,
        headers: headers

      expect(response).to have_http_status(:ok), "checkpoint failed: #{response.body}"
      expect(response.parsed_body["kind"]).to eq("checkpoint")
      expect(note.reload.note_revisions.where(revision_kind: :draft).count).to eq(0)
    end

    it "saves a checkpoint successfully after a draft created wiki-links" do
      dst_note = create(:note, title: "Destino")

      post draft_note_path(note.slug),
        params: {content_markdown: "[[Destino|#{dst_note.id}]]"}.to_json,
        headers: headers

      expect(note.reload.outgoing_links.find_by(dst_note_id: dst_note.id)).to be_present

      post checkpoint_note_path(note.slug),
        params: {content_markdown: "[[Destino|#{dst_note.id}]]"}.to_json,
        headers: headers

      expect(response).to have_http_status(:ok), "checkpoint with links failed: #{response.body}"
      expect(response.parsed_body["kind"]).to eq("checkpoint")
      expect(note.reload.note_revisions.where(revision_kind: :draft)).to eq([])

      link = note.outgoing_links.find_by(dst_note_id: dst_note.id)
      expect(link).to be_present
      expect(link.created_in_revision.revision_kind).to eq("checkpoint")
    end

    it "updates head_revision_id on note" do
      old_head = note.head_revision_id
      post checkpoint_note_path(note.slug),
        params: {content_markdown: "# Nova versão\n\n" + ("conteúdo. " * 30)}.to_json,
        headers: headers

      note.reload
      expect(note.head_revision_id).not_to eq(old_head)
    end
  end

  # Regressão: suporte a caracteres CJK (Japonês, Mandarim, Coreano).
  # Garante que o servidor aceita, armazena e devolve Unicode multibyte corretamente.
  describe "suporte a caracteres CJK" do
    let!(:note) { create(:note, detected_language: "ja-JP") }
    let(:headers) { {"Content-Type" => "application/json", "Accept" => "application/json"} }

    it "salva e recupera conteúdo em Japonês via checkpoint" do
      conteudo = "# 日本語のノート\n\nこれはテストです。日本語の文章をMarkdownで書く。\n\n- 項目一\n- 項目二"

      post checkpoint_note_path(note.slug),
        params: {content_markdown: conteudo}.to_json,
        headers: headers

      expect(response).to have_http_status(:ok)

      get note_path(note.slug)
      expect(response.body).to include("日本語のノート")
      expect(response.body).to include("これはテストです")
    end

    it "salva e recupera conteúdo em Mandarim via draft" do
      conteudo = "# 中文笔记\n\n这是一个测试。用Markdown写中文内容。\n\n- 第一项\n- 第二项"

      post draft_note_path(note.slug),
        params: {content_markdown: conteudo}.to_json,
        headers: headers

      expect(response).to have_http_status(:ok)

      get note_path(note.slug)
      expect(response.body).to include("中文笔记")
    end

    it "salva e recupera conteúdo em Coreano via draft" do
      conteudo = "# 한국어 노트\n\n이것은 테스트입니다.\n\n- 항목 하나\n- 항목 둘"

      post draft_note_path(note.slug),
        params: {content_markdown: conteudo}.to_json,
        headers: headers

      expect(response).to have_http_status(:ok)

      get note_path(note.slug)
      expect(response.body).to include("한국어 노트")
    end
  end

  # Fix: UUID-based note lookup so client-side wiki-link previews work.
  # The client renders [[Display|uuid]] as <a href="/notes/uuid">. Previously
  # set_note only matched by slug, returning 404 for UUID paths.
  describe "GET /notes/:uuid (UUID fallback)" do
    let!(:note) { create(:note, :with_head_revision) }

    it "redirects UUID-based URL to the slug-based URL (301)" do
      get note_path(note.id)
      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to(note_path(note.slug))
    end

    it "still finds note by slug as before" do
      get note_path(note.slug)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /notes/:slug — embedded graph panel" do
    let!(:src_note) { create(:note, :with_head_revision, title: "Origem") }
    let!(:dst_note) { create(:note, :with_head_revision, title: "Destino") }

    before do
      create(:note_link, src_note: src_note, dst_note: dst_note)
    end

    it "does NOT include 'Referenciado por' heading in the preview footer" do
      get note_path(dst_note.slug)
      expect(response.body).not_to include("Referenciado por")
    end

    it "renders the embedded graph panel focused on the current note" do
      get note_path(dst_note.slug)
      expect(response.body).to include('data-controller="graph"')
      expect(response.body).to include(%(data-graph-initial-focused-node-id-value="#{dst_note.id}"))
      expect(response.body).to include(api_graph_path)
    end
  end

  describe "GET /notes/:slug/revisions" do
    let(:note) { create(:note, :with_head_revision) }

    it "returns JSON list of revisions" do
      get revisions_note_path(note.slug),
        headers: {"Accept" => "application/json"}
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json).to be_an(Array)
      expect(json.first).to include("id", "created_at", "is_head")
    end
  end
end
