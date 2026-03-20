require "rails_helper"
require "timeout"

RSpec.describe "AI review", type: :system do
  let!(:user) { create(:user) }
  let!(:note) { create(:note, :with_head_revision) }
  let!(:head_revision) { note.reload.head_revision }

  around do |example|
    original_env = %w[
      AI_ENABLED
      AI_PROVIDER
      AI_ENABLED_PROVIDERS
      OPENAI_API_KEY
      OPENAI_MODEL
      OPENAI_BASE_URL
    ].index_with { |key| ENV[key] }

    ENV["AI_ENABLED"] = "true"
    ENV["AI_PROVIDER"] = "openai"
    ENV["AI_ENABLED_PROVIDERS"] = "openai"
    ENV["OPENAI_API_KEY"] = "secret"
    ENV["OPENAI_MODEL"] = "gpt-4o-mini"
    ENV["OPENAI_BASE_URL"] = "https://example.test/v1"

    example.run
  ensure
    original_env.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  before do
    note.head_revision.update!(content_markdown: "Trecho com erro.\n\nParagrafo final intacto.")

    allow(Ai::ReviewService).to receive(:enqueue) do |note:, note_revision:, capability:, text:, language:, **|
      create(
        :ai_request,
        note_revision: note_revision,
        capability: capability,
        provider: "openai",
        requested_provider: "openai",
        model: "gpt-4o-mini",
        status: "succeeded",
        input_text: text,
        output_text: "Texto corrigido pela IA.",
        metadata: {"language" => language},
        completed_at: Time.current
      )
    end

    sign_in_via_ui(user)
    visit note_path(note.slug)
    expect(page).to have_css(".cm-editor", wait: 10)
  end

  def editor
    find(".cm-content")
  end

  def editor_text
    page.evaluate_script(<<~JS)
      (() => {
        const host = document.querySelector("[data-controller~='codemirror']")
        const controller = window.Stimulus.controllers.find((item) => item.element === host && item.identifier === "codemirror")
        const view = controller.view
        return view.state.doc.toString()
      })()
    JS
  end

  def select_editor_text(target)
    page.execute_script(<<~JS, target)
      (() => {
        const host = document.querySelector("[data-controller~='codemirror']")
        const controller = window.Stimulus.controllers.find((item) => item.element === host && item.identifier === "codemirror")
        const view = controller.view
        const text = view.state.doc.toString()
        const query = arguments[0]
        const from = text.indexOf(query)
        if (from < 0) throw new Error(`Selection target not found: ${query}`)
        view.dispatch({
          selection: { anchor: from, head: from + query.length },
          scrollIntoView: true
        })
        view.focus()
      })()
    JS
  end

  def wait_for_latest_checkpoint(note, timeout: 5)
    Timeout.timeout(timeout) do
      loop do
        revision = note.reload.note_revisions.where(revision_kind: :checkpoint).order(created_at: :desc).first
        return revision if revision.present?

        sleep 0.1
      end
    end
  end

  it "processes the entire document when there is no selection" do
    expect(page).to have_text(/TEMPO REAL|FALLBACK POLLING/i, wait: 5)

    find("button[title='Revisar gramática com IA']").click

    expect(page).to have_css("dialog[open]", text: "Revisão com IA", wait: 5)
    expect(page).to have_text("Texto corrigido pela IA.")
    expect(page).to have_text("Documento inteiro")

    click_button "Aplicar"

    expect(page).to have_css(".cm-content", text: "Texto corrigido pela IA.", wait: 5)
  end

  it "processes only the selected text when the editor has a selection" do
    allow(Ai::ReviewService).to receive(:enqueue) do |note:, note_revision:, capability:, text:, language:, **|
      create(
        :ai_request,
        note_revision: note_revision,
        capability: capability,
        provider: "openai",
        requested_provider: "openai",
        model: "gpt-4o-mini",
        status: "succeeded",
        input_text: text,
        output_text: "Trecho corrigido.",
        metadata: {"language" => language},
        completed_at: Time.current
      )
    end

    editor.click
    select_editor_text("Trecho com erro.")

    find("button[title='Revisar gramática com IA']").click

    expect(page).to have_css("dialog[open]", text: "Revisão com IA", wait: 5)
    expect(page).to have_text("Trecho selecionado")
    expect(page).to have_text("Trecho corrigido.")

    click_button "Aplicar"

    expect(editor_text).to eq("Trecho corrigido.\n\nParagrafo final intacto.")
  end

  it "lets the user choose provider and model before sending the request" do
    allow(Ai::ReviewService).to receive(:status).and_return(
      {
        enabled: true,
        provider: "openai",
        model: "gpt-4o-mini",
        available_providers: ["openai", "anthropic"],
        provider_options: [
          {
            name: "openai",
            label: "OpenAI",
            default_model: "gpt-4o-mini",
            models: ["gpt-4o-mini", "gpt-4.1-mini"],
            selected: true,
            selected_model: "gpt-4o-mini"
          },
          {
            name: "anthropic",
            label: "Anthropic",
            default_model: "claude-3-5-sonnet-latest",
            models: ["claude-3-5-sonnet-latest", "claude-3-7-sonnet-latest"],
            selected: false,
            selected_model: "claude-3-5-sonnet-latest"
          }
        ]
      }
    )

    expect(Ai::ReviewService).to receive(:enqueue).with(hash_including(
      provider_name: "anthropic",
      model_name: "claude-3-7-sonnet-latest"
    )).and_return(
      create(
        :ai_request,
        note_revision: note.head_revision,
        capability: "grammar_review",
        provider: "anthropic",
        requested_provider: "anthropic",
        model: "claude-3-7-sonnet-latest",
        status: "succeeded",
        input_text: note.head_revision.content_markdown,
        output_text: "Texto corrigido pela IA.",
        completed_at: Time.current
      )
    )

    visit note_path(note.slug)

    select "Anthropic", from: "ai-provider-select"
    select "claude-3-7-sonnet-latest", from: "ai-model-select"
    find("button[title='Revisar gramática com IA']").click

    expect(page).to have_css("dialog[open]", text: "Revisão com IA", wait: 5)
    expect(page).to have_text("anthropic: claude-3-7-sonnet-latest")
  end

  it "marks the next checkpoint as AI-generated after the user applies the suggestion" do
    find("button[title='Revisar gramática com IA']").click

    expect(page).to have_css("dialog[open]", text: "Revisão com IA", wait: 5)
    click_button "Aplicar"
    find("button[title='Salvar versão (checkpoint)']").click

    expect(page).to have_text("Salvo", wait: 5)

    revision = wait_for_latest_checkpoint(note)
    expect(revision.ai_generated).to be(true)
  end

  it "shows an explicit remote long-job hint while an ollama request is still running" do
    running_request = create(
      :ai_request,
      note_revision: note.head_revision,
      capability: "grammar_review",
      provider: "ollama",
      requested_provider: "ollama",
      model: "qwen2:1.5b",
      status: "running",
      input_text: note.head_revision.content_markdown,
      started_at: 2.minutes.ago
    )

    allow(Ai::ReviewService).to receive(:enqueue).and_return(running_request)

    find("button[title='Revisar gramática com IA']").click

    expect(page).to have_text("Job remoto longo no AIrch. Pode fechar e voltar depois.", wait: 5)
    expect(page).to have_text("qwen2:1.5b")
    expect(page).to have_text(/2min/, wait: 5)
  end

  it "creates a translated sibling note when accepting a translation result" do
    translated_request = create(
      :ai_request,
      note_revision: note.head_revision,
      capability: "translate",
      provider: "ollama",
      requested_provider: "ollama",
      model: "qwen2:1.5b",
      status: "succeeded",
      input_text: note.head_revision.content_markdown,
      output_text: "# Clinical Summary\n\nTranslated content.",
      metadata: {"language" => "pt-BR", "target_language" => "en-US"},
      completed_at: Time.current
    )
    translated_note = create(:note, :with_head_revision, title: "Clinical Summary", detected_language: "en-US")

    allow(Ai::ReviewService).to receive(:status).and_return(
      {
        enabled: true,
        provider: "ollama",
        model: "qwen2:1.5b",
        available_providers: ["ollama"],
        provider_options: [
          {
            name: "ollama",
            label: "Ollama",
            default_model: "qwen2:1.5b",
            models: ["qwen2:1.5b"],
            selected: true,
            selected_model: "qwen2:1.5b"
          }
        ]
      }
    )
    allow(Ai::ReviewService).to receive(:enqueue).and_return(translated_request)
    expect(Notes::TranslationNoteService).to receive(:call).with(
      source_note: note,
      ai_request: translated_request,
      content: "# Clinical Summary\n\nTranslated content.",
      target_language: "en-US",
      title: "Clinical Summary (Polished)",
      author: user
    ).and_return(translated_note)

    find("button[title='Traduzir com IA']").click

    expect(page).to have_css("dialog[open]", text: "Revisão com IA", wait: 5)
    expect(page).to have_text("Traducao Portugues -> English")
    expect(page).to have_field("Titulo da nova nota", with: "Clinical Summary")
    fill_in "Titulo da nova nota", with: "Clinical Summary (Polished)"
    click_button "Criar nota traduzida"

    expect(page).to have_current_path(note_path(translated_note.slug), wait: 5)
  end

  it "shows the fallback when AI is not configured" do
    ENV["AI_ENABLED"] = "false"
    visit note_path(note.slug)

    find("button[title='Reescrever com IA']").click

    expect(page).to have_css("dialog[open]", text: "IA não configurada", wait: 5)
  end

  it "shows retry feedback while the request is waiting for the next attempt" do
    allow(Ai::ReviewService).to receive(:enqueue) do |note:, note_revision:, capability:, text:, language:, **|
      request = create(
        :ai_request,
        note_revision: note_revision,
        capability: capability,
        provider: "openai",
        requested_provider: "openai",
        model: "gpt-4o-mini",
        status: "retrying",
        attempts_count: 1,
        max_attempts: 3,
        input_text: text,
        error_message: "openai indisponivel",
        last_error_kind: "transient",
        next_retry_at: 2.seconds.from_now,
        metadata: {"language" => language}
      )

      Thread.new do
        sleep 1.2
        request.update!(
          status: "succeeded",
          output_text: "Texto corrigido pela IA.",
          completed_at: Time.current,
          next_retry_at: nil,
          error_message: nil,
          last_error_kind: nil
        )
      end

      request
    end

    find("button[title='Revisar gramática com IA']").click

    expect(page).to have_text("Tentando novamente", wait: 5)
    expect(page).to have_text("Tentativa 1 de 3", wait: 5)
    expect(page).to have_text("openai indisponivel", wait: 5)
    expect(page).to have_css("dialog[open]", text: "Texto corrigido pela IA.", wait: 5)
  end

  it "cancels the in-flight request from the processing overlay" do
    request = nil

    allow(Ai::ReviewService).to receive(:enqueue) do |note:, note_revision:, capability:, text:, language:, **|
      request = create(
        :ai_request,
        note_revision: note_revision,
        capability: capability,
        provider: "openai",
        requested_provider: "openai",
        model: "gpt-4o-mini",
        status: "retrying",
        attempts_count: 1,
        max_attempts: 3,
        input_text: text,
        error_message: "openai indisponivel",
        last_error_kind: "transient",
        next_retry_at: 15.seconds.from_now,
        metadata: {"language" => language}
      )
    end

    find("button[title='Revisar gramática com IA']").click

    expect(page).to have_text("Tentando novamente", wait: 5)
    click_button "Cancelar"

    expect(page).to have_no_text("Tentando novamente", wait: 5)
    expect(request.reload.status).to eq("canceled")
  end

  it "shows recent AI executions in the history dialog" do
      create(
        :ai_request,
        note_revision: head_revision,
        capability: "grammar_review",
        provider: "openai",
        requested_provider: "openai",
      model: "gpt-4o-mini",
      status: "succeeded",
      attempts_count: 1,
      started_at: 3.seconds.ago,
      completed_at: 1.second.ago,
      output_text: "Texto corrigido."
    )

      create(
        :ai_request,
        note_revision: head_revision,
        capability: "rewrite",
        provider: "openai",
        requested_provider: "openai",
      model: "gpt-4o-mini",
      status: "failed",
      attempts_count: 3,
      error_message: "Falha remota"
    )

    find("button[title='Histórico de IA']").click

    expect(page).to have_css("dialog[open]", text: "Histórico de IA", wait: 5)
    expect(page).to have_text("Revisao gramatical", wait: 5)
    expect(page).to have_text("Reescrita", wait: 5)
    expect(page).to have_text("Concluida", wait: 5)
    expect(page).to have_text("Falhou", wait: 5)
    expect(page).to have_text("Falha remota", wait: 5)

    click_button "Falhas"
    expect(page).to have_text("Falha remota", wait: 5)
    expect(page).to have_no_text("Texto corrigido.", wait: 5)

    click_button "Concluídas"
    expect(page).to have_text("Texto corrigido.", wait: 5)
    expect(page).to have_no_text("Falha remota", wait: 5)
  end
end
