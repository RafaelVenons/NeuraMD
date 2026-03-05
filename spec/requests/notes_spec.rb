require "rails_helper"

RSpec.describe "Notes", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /notes" do
    it "returns http success" do
      create(:note, :with_head_revision)
      get notes_path
      expect(response).to have_http_status(:ok)
    end

    it "lists only active notes" do
      active = create(:note, title: "Active")
      deleted = create(:note, title: "Deleted", deleted_at: Time.current)
      get notes_path
      expect(response.body).to include("Active")
      expect(response.body).not_to include("Deleted")
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
      note = Note.last
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
