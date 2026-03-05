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

  # Regressão: conteúdo digitado não reaparecia ao reabrir o editor.
  # Causa raiz: debounce configurado em 60s (deveria ser 3s) — usuário saía
  # antes do save disparar. O editor reabria com conteúdo vazio.
  # Nota: o bug do debounce em si é configuração de front-end (data-attribute na
  # view), não simulável com request specs. Este spec garante o fluxo server-side:
  # autosave salva e reabrir o editor entrega o conteúdo correto.
  describe "persistência de conteúdo entre sessões" do
    let!(:note) { create(:note) }
    let(:headers) { {"Content-Type" => "application/json", "Accept" => "application/json"} }
    let(:conteudo) { "# Título\n\n" + ("Parágrafo de conteúdo longo. " * 15) }

    it "conteúdo salvo via autosave reaparece ao reabrir o editor" do
      post autosave_note_path(note.slug),
        params: {content_markdown: conteudo}.to_json,
        headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["created"]).to be(true)

      get note_path(note.slug)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(CGI.escapeHTML(conteudo))
    end

    it "nota sem revisão abre editor com conteúdo vazio (não levanta erro)" do
      get note_path(note.slug)

      expect(response).to have_http_status(:ok)
    end
  end

  # Regressão: suporte a caracteres CJK (Japonês, Mandarim, Coreano) no autosave.
  # Garante que o servidor aceita, armazena e devolve Unicode multibyte corretamente.
  # Testar manualmente no iOS: Settings > General > Keyboard > Add Keyboard > Japanese (Romaji),
  # digitar no editor e confirmar que o IME composition bar aparece e o texto é aceito.
  describe "suporte a caracteres CJK" do
    let!(:note) { create(:note, detected_language: "ja-JP") }
    let(:headers) { {"Content-Type" => "application/json", "Accept" => "application/json"} }

    it "salva e recupera conteúdo em Japonês" do
      conteudo = "# 日本語のノート\n\nこれはテストです。日本語の文章をMarkdownで書く。\n\n- 項目一\n- 項目二"

      post autosave_note_path(note.slug),
        params: {content_markdown: conteudo}.to_json,
        headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["created"]).to be(true)

      get note_path(note.slug)
      expect(response.body).to include("日本語のノート")
      expect(response.body).to include("これはテストです")
    end

    it "salva e recupera conteúdo em Mandarim" do
      conteudo = "# 中文笔记\n\n这是一个测试。用Markdown写中文内容。\n\n- 第一项\n- 第二项"

      post autosave_note_path(note.slug),
        params: {content_markdown: conteudo}.to_json,
        headers: headers

      expect(response).to have_http_status(:ok)

      get note_path(note.slug)
      expect(response.body).to include("中文笔记")
    end

    it "salva e recupera conteúdo em Coreano" do
      conteudo = "# 한국어 노트\n\n이것은 테스트입니다.\n\n- 항목 하나\n- 항목 둘"

      post autosave_note_path(note.slug),
        params: {content_markdown: conteudo}.to_json,
        headers: headers

      expect(response).to have_http_status(:ok)

      get note_path(note.slug)
      expect(response.body).to include("한국어 노트")
    end
  end

  describe "POST /notes/:slug/autosave" do
    let!(:note) { create(:note, :with_head_revision) }
    let(:headers) { {"Content-Type" => "application/json", "Accept" => "application/json"} }

    it "creates a revision for significant change" do
      long_content = "A" * 300
      expect {
        post autosave_note_path(note.slug),
          params: {content_markdown: long_content}.to_json,
          headers: headers
      }.to change(NoteRevision, :count).by(1)

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["created"]).to be(true)
      expect(json["revision_id"]).to be_present
    end

    it "does not create revision for tiny change" do
      original = note.head_revision.content_markdown
      tiny_change = original + "."

      expect {
        post autosave_note_path(note.slug),
          params: {content_markdown: tiny_change}.to_json,
          headers: headers
      }.not_to change(NoteRevision, :count)

      json = response.parsed_body
      expect(json["created"]).to be(false)
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
