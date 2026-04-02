require "rails_helper"
require "securerandom"
require "rake"

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

  describe "POST /notes/:slug/create_from_promise" do
    let(:note) { create(:note, :with_head_revision) }

    it "creates a blank note from a promise title" do
      note
      expect {
        post create_from_promise_note_path(note.slug),
          params: { title: "Nova promessa", mode: "blank" },
          as: :json
      }.to change(Note, :count).by(1)

      expect(response).to have_http_status(:created)
      created = Note.order(created_at: :desc).first
      expect(created.title).to eq("Nova promessa")
      expect(created.detected_language).to eq(note.detected_language)
      expect(response.parsed_body).to include(
        "note_id" => created.id,
        "note_slug" => created.slug,
        "note_title" => "Nova promessa",
        "created" => true,
        "seeded" => false
      )
    end

    it "creates an AI-seeded note from a promise title" do
      note
      provider = instance_double(Ai::OllamaProvider, name: "ollama", model: "qwen2.5:1.5b", base_url: "http://example.test:11434")
      allow(Ai::ProviderRegistry).to receive(:enabled?).and_return(true)
      allow(Ai::ProviderRegistry).to receive(:resolve_selection).and_return(
        {
          name: "ollama",
          model: "qwen2.5:1.5b",
          selection_strategy: "automatic",
          selection_reason: "seed_note_short"
        }
      )
      allow(Ai::ProviderRegistry).to receive(:build).and_return(provider)

      expect {
        post create_from_promise_note_path(note.slug),
          params: { title: "Nova promessa", mode: "ai" },
          as: :json
      }.to change(Note, :count).by(1)
        .and change(AiRequest, :count).by(1)

      expect(response).to have_http_status(:created)
      created = Note.order(created_at: :desc).first
      expect(created.head_revision).to be_nil
      request_record = AiRequest.recent_first.first
      expect(request_record.capability).to eq("seed_note")
      expect(request_record.metadata).to include(
        "promise_note_id" => created.id,
        "promise_note_title" => "Nova promessa",
        "promise_source_note_id" => note.id
      )
      expect(request_record.input_text).to include("Write a markdown note about: Nova promessa")
      expect(request_record.input_text).to include("ENTIRELY about")
      expect(response.parsed_body).to include(
        "note_id" => created.id,
        "request_id" => request_record.id,
        "request_status" => "queued",
        "created" => true,
        "seeded" => false
      )
    end

    it "anchors the AI request to the head revision when the source note also has a draft" do
      note
      draft_revision = create(:note_revision, note: note, revision_kind: :draft, content_markdown: "# Rascunho\n\nConteudo temporario")
      provider = instance_double(Ai::OllamaProvider, name: "ollama", model: "qwen2.5:1.5b", base_url: "http://example.test:11434")
      allow(Ai::ProviderRegistry).to receive(:enabled?).and_return(true)
      allow(Ai::ProviderRegistry).to receive(:resolve_selection).and_return(
        {
          name: "ollama",
          model: "qwen2.5:1.5b",
          selection_strategy: "automatic",
          selection_reason: "seed_note_short"
        }
      )
      allow(Ai::ProviderRegistry).to receive(:build).and_return(provider)

      post create_from_promise_note_path(note.slug),
        params: { title: "Nova promessa com draft", mode: "ai" },
        as: :json

      expect(response).to have_http_status(:created)

      request_record = AiRequest.recent_first.first
      expect(request_record.note_revision_id).to eq(note.head_revision_id)
      expect(request_record.note_revision_id).not_to eq(draft_revision.id)
    end

    it "reuses an existing active note with the same title instead of creating a duplicate" do
      existing = create(:note, :with_head_revision, title: "Nova promessa")
      note

      expect {
        post create_from_promise_note_path(note.slug),
          params: { title: "Nova promessa", mode: "ai" },
          as: :json
      }.not_to change(Note, :count)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include(
        "note_id" => existing.id,
        "created" => false,
        "seeded" => true
      )
    end

    it "returns JSON when an unexpected error happens during AI promise creation" do
      note
      allow(Notes::PromiseCreationService).to receive(:call).and_raise(StandardError, "boom")

      post create_from_promise_note_path(note.slug),
        params: { title: "Nova promessa", mode: "ai" },
        as: :json

      expect(response).to have_http_status(:internal_server_error)
      expect(response.media_type).to eq("application/json")
      expect(response.parsed_body).to include("error" => "Falha interna ao criar nota com IA.")
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

    it "redirects to real slug when accessed via alias name" do
      create(:note_alias, note: note, name: "My Alias")
      get note_path("my alias")
      expect(response).to redirect_to(note_path(note.slug))
      expect(response).to have_http_status(:moved_permanently)
    end

    it "returns 404 when alias belongs to deleted note" do
      create(:note_alias, note: note, name: "Ghost Alias")
      note.soft_delete!
      get note_path("ghost alias")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /notes/search" do
    let(:suffix) { SecureRandom.hex(4) }
    let!(:exactish) { create(:note, :with_head_revision, title: "Cardio Geral #{suffix}") }
    let!(:fuzzy) { create(:note, :with_head_revision, title: "Cardiologia Avancada #{suffix}") }
    let!(:other) { create(:note, :with_head_revision, title: "Neurologia") }

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

    it "omits notes without latest content from title search and finder results" do
      visible = create(:note, title: "Cardio visivel")
      visible_revision = create(:note_revision, note: visible, content_markdown: "Conteudo de cardio visivel")
      visible.update_columns(head_revision_id: visible_revision.id)

      hidden = create(:note, title: "Cardio oculto", head_revision: nil)

      get search_notes_path, params: { q: "cardio" }

      expect(response).to have_http_status(:ok)
      titles = response.parsed_body.map { |item| item["title"] }
      expect(titles).to include("Cardio visivel")
      expect(titles).not_to include("Cardio oculto")

      get search_notes_path, params: { q: "cardio", mode: "finder", limit: 5 }

      expect(response).to have_http_status(:ok)
      finder_titles = response.parsed_body["results"].map { |item| item["title"] }
      expect(finder_titles).to include("Cardio visivel")
      expect(finder_titles).not_to include("Cardio oculto")
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

    it "returns matched_alias in autocomplete when match is via alias" do
      note_with_alias = create(:note, :with_head_revision, title: "Hematologia Profunda")
      create(:note_alias, note: note_with_alias, name: "Blood Science")

      get search_notes_path, params: {q: "blood"}

      expect(response).to have_http_status(:ok)
      match = response.parsed_body.find { |n| n["id"] == note_with_alias.id }
      expect(match).to be_present
      expect(match["matched_alias"]).to eq("Blood Science")
    end

    it "does not include matched_alias when match is via title only" do
      titled = create(:note, :with_head_revision, title: "Pneumologia Avancada")

      get search_notes_path, params: {q: "pneumo"}

      expect(response).to have_http_status(:ok)
      match = response.parsed_body.find { |n| n["id"] == titled.id }
      expect(match).to be_present
      expect(match).not_to have_key("matched_alias")
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

    it "ignores slug parameter in update params" do
      original_slug = note.slug
      patch note_path(note.slug), params: {note: {slug: "hacked-slug"}}
      expect(note.reload.slug).to eq(original_slug)
    end

    it "changes slug and creates redirect when title changes" do
      old_slug = note.slug
      patch note_path(note.slug), params: {note: {title: "Titulo Completamente Novo"}}
      note.reload
      expect(note.slug).to eq("titulo-completamente-novo")
      expect(SlugRedirect.find_by(slug: old_slug, note: note)).to be_present
    end
  end

  describe "GET /notes/:old_slug (slug redirect)" do
    it "redirects old slug to new slug after rename (301)" do
      note = create(:note, title: "Antes")
      old_slug = note.slug
      Notes::RenameService.call(note: note, new_title: "Depois")

      get note_path(old_slug)
      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to(note_path("depois"))
    end

    it "redirects chain of old slugs to current slug" do
      note = create(:note, title: "A")
      Notes::RenameService.call(note: note, new_title: "B")
      Notes::RenameService.call(note: note, new_title: "C")

      get note_path("a")
      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to(note_path("c"))
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

  describe "POST /notes/:slug/restore" do
    it "restores a soft-deleted note" do
      note = create(:note, title: "Restauravel")
      note.soft_delete!
      post restore_note_path(note.slug)
      expect(response).to have_http_status(:redirect)
      expect(note.reload.deleted?).to be(false)
    end

    it "returns 404 for unknown slug" do
      post restore_note_path("inexistente")
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for active (non-deleted) note" do
      note = create(:note)
      post restore_note_path(note.slug)
      expect(response).to have_http_status(:not_found)
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

    it "marks checkpoint metadata when accepting an AI request" do
      request_record = create(
        :ai_request,
        note_revision: note.head_revision,
        status: "succeeded",
        metadata: {"language" => "pt-BR"}
      )

      post checkpoint_note_path(note.slug),
        params: {
          content_markdown: "# Revisão aceita\n\n" + ("conteúdo. " * 20),
          ai_request_id: request_record.id
        }.to_json,
        headers: headers

      expect(response).to have_http_status(:ok)

      revision = note.reload.note_revisions.order(created_at: :desc).first
      expect(revision.ai_generated).to be(true)
      expect(request_record.reload.metadata).to include("accepted_checkpoint_revision_id" => revision.id)
      expect(request_record.metadata["accepted_at"]).to be_present
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

    it "includes properties_data in each revision" do
      Notes::CheckpointService.call(
        note: note, content: "v2", author: user,
        properties_data: {"status" => "draft"}
      )

      get revisions_note_path(note.slug),
        headers: {"Accept" => "application/json"}

      json = response.parsed_body
      expect(json.first).to have_key("properties_data")
      expect(json.first["properties_data"]).to include("status" => "draft")
    end

    it "includes properties_diff showing changes between revisions" do
      Notes::CheckpointService.call(
        note: note, content: "v2", author: user,
        properties_data: {"status" => "draft"}
      )
      Notes::CheckpointService.call(
        note: note, content: "v3", author: user,
        properties_data: {"status" => "published", "priority" => 1}
      )

      get revisions_note_path(note.slug),
        headers: {"Accept" => "application/json"}

      json = response.parsed_body
      latest = json.first
      expect(latest).to have_key("properties_diff")
      expect(latest["properties_diff"]["added"]).to include("priority")
      expect(latest["properties_diff"]["changed"]).to include("status")
    end
  end

  describe "POST /notes/:slug/revisions/:revision_id/restore" do
    let(:note) { create(:note, :with_head_revision) }

    it "restores properties_data from the source revision" do
      rev_a = Notes::CheckpointService.call(
        note: note, content: "content A", author: user,
        properties_data: {"status" => "draft", "priority" => 1}
      ).revision

      Notes::CheckpointService.call(
        note: note, content: "content B", author: user,
        properties_data: {"status" => "published"}
      )

      post restore_revision_note_path(note.slug, rev_a.id),
        headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      new_head = note.reload.head_revision
      expect(new_head.properties_data).to eq({"status" => "draft", "priority" => 1})
    end
  end

  describe "rename integrity (EPIC-00.1)" do
    let!(:author) { create(:user) }

    it "wikilinks survive rename — NoteLink stays active" do
      source = create(:note, title: "Source")
      target = create(:note, title: "Target")
      revision = create(:note_revision, note: source, revision_kind: :checkpoint,
        content_markdown: "Link to [[Target|#{target.id}]]", author: author)
      source.update_columns(head_revision_id: revision.id)
      NoteLink.create!(src_note_id: source.id, dst_note_id: target.id, created_in_revision: revision)

      Notes::RenameService.call(note: target, new_title: "Target Renomeado")

      link = NoteLink.find_by(src_note_id: source.id, dst_note_id: target.id)
      expect(link).to be_present
      expect(source.head_revision.content_markdown).to include(target.id)
    end

    it "search finds note by new title after rename" do
      note = create(:note, title: "Cardio Geral")
      Notes::CheckpointService.call(note: note, content: "conteudo", author: author)
      Notes::RenameService.call(note: note, new_title: "Cardiologia Basica")

      get search_notes_path(q: "Cardiologia", format: :json)
      titles = response.parsed_body.map { |n| n["title"] }
      expect(titles).to include("Cardiologia Basica")
    end

    it "search does not find note by old title after rename" do
      note = create(:note, title: "Titulo Unico Antigo")
      Notes::CheckpointService.call(note: note, content: "conteudo", author: author)
      Notes::RenameService.call(note: note, new_title: "Titulo Unico Novo")

      get search_notes_path(q: "Titulo Unico Antigo", format: :json)
      titles = response.parsed_body.map { |n| n["title"] }
      expect(titles).not_to include("Titulo Unico Antigo")
    end

    it "graph API uses current slug after rename" do
      note = create(:note, title: "Grafo Nota")
      Notes::CheckpointService.call(note: note, content: "conteudo grafo", author: author)
      Notes::RenameService.call(note: note, new_title: "Grafo Renomeado")

      get api_graph_path, headers: {"Accept" => "application/json"}
      json = response.parsed_body
      node = json["notes"]&.find { |n| n["id"] == note.id }
      expect(node).to be_present
      expect(node["slug"]).to eq("grafo-renomeado")
    end

    it "old slug redirect works after note is accessed via UUID" do
      note = create(:note, :with_head_revision, title: "UUID Test")
      Notes::RenameService.call(note: note, new_title: "UUID Test Renamed")

      get note_path(note.id)
      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to(note_path("uuid-test-renamed"))
    end

    it "shell JSON request via old slug redirects to current slug" do
      note = create(:note, :with_head_revision, title: "Shell Test")
      old_slug = note.slug
      Notes::RenameService.call(note: note, new_title: "Shell Renamed")

      get note_path(old_slug), headers: {"Accept" => "application/json"}
      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to(note_path("shell-renamed"))

      # Following the redirect returns the full shell payload
      get note_path("shell-renamed"), headers: {"Accept" => "application/json"}
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json.dig("note", "slug")).to eq("shell-renamed")
      expect(json.dig("note", "title")).to eq("Shell Renamed")
    end

    it "HTML request to old slug redirects to new slug" do
      note = create(:note, :with_head_revision, title: "Redirect HTML")
      old_slug = note.slug
      Notes::RenameService.call(note: note, new_title: "Redirect HTML New")

      get note_path(old_slug)
      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to(note_path("redirect-html-new"))
    end
  end

  describe "critical operation regressions (EPIC-00.4)" do
    before(:all) { Rails.application.load_tasks }
    let!(:author) { create(:user) }

    # -- delete / restore --

    it "delete hides note from search" do
      note = create(:note, title: "Deletavel Unico")
      Notes::CheckpointService.call(note: note, content: "corpo", author: author)
      note.soft_delete!

      get search_notes_path(q: "Deletavel Unico", format: :json)
      titles = response.parsed_body.map { |n| n["title"] }
      expect(titles).not_to include("Deletavel Unico")
    end

    it "delete hides note from graph" do
      note = create(:note, title: "Grafo Deletavel")
      Notes::CheckpointService.call(note: note, content: "corpo grafo", author: author)
      note.soft_delete!

      get api_graph_path, headers: {"Accept" => "application/json"}
      ids = response.parsed_body["notes"]&.map { |n| n["id"] } || []
      expect(ids).not_to include(note.id)
    end

    it "restore brings note back to search" do
      note = create(:note, title: "Restauravel Unico")
      Notes::CheckpointService.call(note: note, content: "corpo", author: author)
      note.soft_delete!
      note.restore!

      get search_notes_path(q: "Restauravel Unico", format: :json)
      titles = response.parsed_body.map { |n| n["title"] }
      expect(titles).to include("Restauravel Unico")
    end

    it "restore brings note back to graph" do
      note = create(:note, title: "Grafo Restauravel")
      Notes::CheckpointService.call(note: note, content: "corpo", author: author)
      note.soft_delete!
      note.restore!

      get api_graph_path, headers: {"Accept" => "application/json"}
      ids = response.parsed_body["notes"]&.map { |n| n["id"] } || []
      expect(ids).to include(note.id)
    end

    # -- add / remove link --

    it "checkpoint creates link and graph reflects it" do
      source = create(:note, title: "Link Source")
      target = create(:note, title: "Link Target")
      Notes::CheckpointService.call(note: target, content: "target body", author: author)
      Notes::CheckpointService.call(note: source, content: "ref [[Link Target|#{target.id}]]", author: author)

      get api_graph_path, headers: {"Accept" => "application/json"}
      json = response.parsed_body
      edge = json["links"]&.find { |l| l["src_note_id"] == source.id && l["dst_note_id"] == target.id }
      expect(edge).to be_present
    end

    it "removing link from content deactivates it in graph" do
      source = create(:note, title: "Unlink Source")
      target = create(:note, title: "Unlink Target")
      Notes::CheckpointService.call(note: target, content: "target body", author: author)
      Notes::CheckpointService.call(note: source, content: "ref [[Unlink Target|#{target.id}]]", author: author)

      # Remove the link from content
      Notes::CheckpointService.call(note: source, content: "no more links", author: author)

      link = NoteLink.find_by(src_note_id: source.id, dst_note_id: target.id)
      expect(link.active).to be false

      get api_graph_path, headers: {"Accept" => "application/json"}
      json = response.parsed_body
      edge = json["links"]&.find { |l| l["src_note_id"] == source.id && l["dst_note_id"] == target.id }
      expect(edge).to be_nil
    end

    # -- reindex --

    it "reindex restores orphaned link" do
      source = create(:note, title: "Reindex Source")
      target = create(:note, title: "Reindex Target")
      Notes::CheckpointService.call(note: target, content: "target", author: author)
      Notes::CheckpointService.call(note: source, content: "ref [[Reindex Target|#{target.id}]]", author: author)

      # Simulate orphaned state
      NoteLink.where(src_note_id: source.id).update_all(active: false)
      expect(NoteLink.find_by(src_note_id: source.id, dst_note_id: target.id).active).to be false

      Rake::Task["notes:reindex"].reenable
      Rake::Task["notes:reindex"].invoke

      expect(NoteLink.find_by(src_note_id: source.id, dst_note_id: target.id).active).to be true
    end

    # -- preview (backlinks) --

    it "backlinks include linking note after checkpoint" do
      source = create(:note, title: "Backlink Source")
      target = create(:note, title: "Backlink Target")
      Notes::CheckpointService.call(note: target, content: "target", author: author)
      Notes::CheckpointService.call(note: source, content: "ref [[Backlink Target|#{target.id}]]", author: author)

      get note_path(target.slug), headers: {"Accept" => "application/json"}
      html = response.parsed_body.dig("html", "backlinks")
      expect(html).to include("Backlink Source")
    end

    it "backlinks update after linking note is renamed" do
      source = create(:note, title: "Rename Backlink Source")
      target = create(:note, title: "Rename Backlink Target")
      Notes::CheckpointService.call(note: target, content: "target", author: author)
      Notes::CheckpointService.call(note: source, content: "ref [[Rename Backlink Target|#{target.id}]]", author: author)

      Notes::RenameService.call(note: source, new_title: "Source Renomeado")

      get note_path(target.slug), headers: {"Accept" => "application/json"}
      html = response.parsed_body.dig("html", "backlinks")
      expect(html).to include("Source Renomeado")
      expect(html).not_to include("Rename Backlink Source")
    end

    # -- search basics --

    it "search finds note by content after checkpoint" do
      note = create(:note, title: "Busca Conteudo")
      Notes::CheckpointService.call(note: note, content: "mitocondria powerhouse", author: author)

      get search_notes_path(q: "mitocondria", mode: "finder", format: :json)
      slugs = response.parsed_body["results"]&.map { |n| n["slug"] } || []
      expect(slugs).to include(note.slug)
    end

    # -- graph basics --

    it "graph includes note with head revision" do
      note = create(:note, title: "Grafo Basico")
      Notes::CheckpointService.call(note: note, content: "conteudo", author: author)

      get api_graph_path, headers: {"Accept" => "application/json"}
      ids = response.parsed_body["notes"]&.map { |n| n["id"] } || []
      expect(ids).to include(note.id)
    end

    it "graph excludes note without head revision" do
      note = create(:note, title: "Sem Head")

      get api_graph_path, headers: {"Accept" => "application/json"}
      ids = response.parsed_body["notes"]&.map { |n| n["id"] } || []
      expect(ids).not_to include(note.id)
    end
  end
end
