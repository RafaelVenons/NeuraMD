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

  def wait_until(timeout: 5)
    Timeout.timeout(timeout) do
      loop do
        result = yield
        return result if result

        sleep 0.1
      end
    end
  end

  def open_completed_queue_card(wait: 8)
    expect(page).to have_css("[data-queue-status='succeeded']", wait:)
    find("[data-queue-status='succeeded']").click
  end

  def expect_ai_workspace(text:, wait: 5)
    # With the new queue-first flow, succeeded requests show as green cards
    # instead of auto-opening. Click the card if workspace is still hidden.
    unless page.has_css?("[data-ai-review-target='workspace']:not(.hidden)", wait: 2)
      if page.has_css?("[data-queue-status='succeeded']", wait:)
        find("[data-queue-status='succeeded']").click
      end
    end

    expect(page).to have_css("[data-ai-review-target='workspace']:not(.hidden)", wait:)
    if page.has_css?("[data-ai-review-target='proposalDiff']", visible: :visible, wait:)
      visible_text = find("[data-ai-review-target='proposalDiff']", visible: :visible, wait:).text.gsub(/\n+/, "\n")
      expected_text = text.gsub(/\n+/, "\n")
      expect(visible_text).to include(expected_text)
    elsif page.has_css?("textarea[data-ai-review-target='correctedText']", visible: :visible, wait:)
      expect(find("textarea[data-ai-review-target='correctedText']", visible: :visible, wait:).value).to include(text)
    else
      expect(page).to have_css("[data-ai-review-target='workspace']:not(.hidden)", text:, wait:)
    end
  end

  def replace_editor_text(text)
    page.execute_script(<<~JS, text)
      (() => {
        const host = document.querySelector("[data-controller~='codemirror']")
        const controller = window.Stimulus.controllers.find((item) => item.element === host && item.identifier === "codemirror")
        const view = controller.view
        view.dispatch({
          changes: { from: 0, to: view.state.doc.length, insert: arguments[0] }
        })
        view.focus()
      })()
    JS
  end

  def force_ai_queue_fallback_polling
    page.execute_script(<<~JS)
      (() => {
        const host = document.querySelector("[data-controller~='ai-review']")
        const controller = window.Stimulus.controllers.find((item) => item.element === host && item.identifier === "ai-review")
        controller._setTransportState(false)
      })()
    JS
  end

  def refresh_ai_queue_now
    page.execute_script(<<~JS)
      (() => {
        const host = document.querySelector("[data-controller~='ai-review']")
        const controller = window.Stimulus.controllers.find((item) => item.element === host && item.identifier === "ai-review")
        controller.refreshQueue()
      })()
    JS
  end

  def replace_ai_suggested_text(text)
    page.execute_script(<<~JS, text)
      (() => {
        const element = document.querySelector("[data-ai-review-target='proposalDiff']")
        element.textContent = arguments[0]
        element.dispatchEvent(new Event("input", { bubbles: true }))
      })()
    JS
  end

  def choose_ai_option(button_title, option_text = /Automatico/)
    find("button[title='#{button_title}']").click
    expect(page).to have_css("[data-ai-review-target='requestMenu']:not(.hidden)", wait: 5)
    within("[data-ai-review-target='requestMenu']") do
      find("button", text: option_text, match: :first).click
    end
  end

  def queue_titles
    page.evaluate_script(<<~JS)
      (() => {
        const dock = document.querySelector("[data-ai-review-target='queueDock']")
        if (!dock) return []
        return Array.from(dock.querySelectorAll("article")).map((card) => {
          const paragraphs = card.querySelectorAll("p")
          return paragraphs[1] ? paragraphs[1].textContent.trim() : ""
        })
      })()
    JS
  end

  def wait_for_request_queue_position(request, position, timeout: Capybara.default_max_wait_time)
    Timeout.timeout(timeout) do
      loop do
        request.reload
        return if request.queue_position == position

        sleep 0.1
      end
    end
  end

  def dispatch_request_update(request)
    payload = request.reload.realtime_payload.to_json
    page.execute_script(<<~JS, payload)
      const [detail] = arguments
      const root = document.getElementById("editor-root")
      root.dispatchEvent(new CustomEvent("ai-request:update", {
        bubbles: true,
        detail: JSON.parse(detail)
      }))
    JS
  end

  def drag_queue_card_after(source_id, target_id)
    start_queue_drag(source_id)
    drag_queue_over(target_id, position: :bottom)
    finish_queue_drag(target_id, position: :bottom)
  end

  def start_queue_drag(source_id)
    page.execute_script(<<~JS, source_id)
      const [sourceId] = arguments
      const source = document.querySelector(`[data-request-id="${sourceId}"]`)
      if (!source) throw new Error("Queue card not found")
      const rect = source.getBoundingClientRect()
      const pointerId = 1
      const startX = rect.left + (rect.width / 2)
      const startY = rect.top + 6

      window.__nmQueuePointerDrag = { pointerId }

      source.dispatchEvent(new PointerEvent("pointerdown", {
        bubbles: true,
        cancelable: true,
        pointerId,
        pointerType: "mouse",
        button: 0,
        buttons: 1,
        clientX: startX,
        clientY: startY
      }))

      window.dispatchEvent(new PointerEvent("pointermove", {
        bubbles: true,
        cancelable: true,
        pointerId,
        pointerType: "mouse",
        button: 0,
        buttons: 1,
        clientX: startX,
        clientY: startY + 12
      }))
    JS
  end

  def drag_queue_over(target_id, position: :bottom)
    client_y = page.evaluate_script(<<~JS, target_id, position.to_s)
      (() => {
        const [targetId, position] = arguments
        const target = document.querySelector(`[data-request-id="${targetId}"]`)
        if (!target) throw new Error("Queue card not found")
        const rect = target.getBoundingClientRect()
        return position === "top" ? rect.top + 2 : rect.bottom - 2
      })()
    JS

    page.execute_script(<<~JS, target_id, client_y)
      const [targetId, clientY] = arguments
      const target = document.querySelector(`[data-request-id="${targetId}"]`)
      if (!target) throw new Error("Queue card not found")
      const pointerId = window.__nmQueuePointerDrag?.pointerId || 1
      const rect = target.getBoundingClientRect()
      const clientX = rect.left + (rect.width / 2)

      window.dispatchEvent(new PointerEvent("pointermove", {
        bubbles: true,
        cancelable: true,
        pointerId,
        pointerType: "mouse",
        button: 0,
        buttons: 1,
        clientX,
        clientY
      }))
    JS
  end

  def finish_queue_drag(target_id, position: :bottom)
    client_y = page.evaluate_script(<<~JS, target_id, position.to_s)
      (() => {
        const [targetId, position] = arguments
        const target = document.querySelector(`[data-request-id="${targetId}"]`)
        if (!target) throw new Error("Queue card not found")
        const rect = target.getBoundingClientRect()
        return position === "top" ? rect.top + 2 : rect.bottom - 2
      })()
    JS

    page.execute_script(<<~JS, target_id, client_y)
      const [targetId, clientY] = arguments
      const target = document.querySelector(`[data-request-id="${targetId}"]`)
      if (!target) throw new Error("Queue card not found")
      const pointerId = window.__nmQueuePointerDrag?.pointerId || 1
      const rect = target.getBoundingClientRect()
      const clientX = rect.left + (rect.width / 2)

      window.dispatchEvent(new PointerEvent("pointerup", {
        bubbles: true,
        cancelable: true,
        pointerId,
        pointerType: "mouse",
        button: 0,
        buttons: 0,
        clientX,
        clientY
      }))
      window.__nmQueuePointerDrag = null
    JS
  end

  it "processes the entire document when there is no selection" do
    choose_ai_option("Revisar gramática com IA")

    expect_ai_workspace(text: "Texto corrigido pela IA.")
    expect(page).to have_css(".cm-ai-diff-deleted", minimum: 1, wait: 5)
    expect(editor_text).to eq("Trecho com erro.\n\nParagrafo final intacto.")

    click_button "Aplicar"

    expect(page).to have_css(".cm-content", text: "Texto corrigido pela IA.", wait: 5)
  end

  it "clears the red deletion diff after applying and resuming normal editing" do
    choose_ai_option("Revisar gramática com IA")

    expect_ai_workspace(text: "Texto corrigido pela IA.")
    expect(page).to have_css(".cm-ai-diff-deleted", minimum: 1, wait: 5)

    click_button "Aplicar"
    editor.click
    editor.send_keys(" Ajuste manual")

    expect(page).to have_no_css(".cm-ai-diff-deleted", wait: 5)
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

    choose_ai_option("Revisar gramática com IA")

    expect_ai_workspace(text: "Trecho corrigido.\n\nParagrafo final intacto.")
    expect(page).to have_css(".cm-ai-diff-deleted", minimum: 1, wait: 5)
    expect(editor_text).to eq("Trecho com erro.\n\nParagrafo final intacto.")

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
    choose_ai_option("Revisar gramática com IA", /Anthropic.*claude-3-7-sonnet-latest/)

    expect_ai_workspace(text: "Texto corrigido pela IA.")
    expect(page).to have_css(".cm-ai-diff-deleted", minimum: 1, wait: 5)
    expect(page).to have_no_text("openai: gpt-4o-mini")
  end

  it "marks the next checkpoint as AI-generated after the user applies the suggestion" do
    choose_ai_option("Revisar gramática com IA")

    expect_ai_workspace(text: "Texto corrigido pela IA.")
    click_button "Aplicar"
    find("button[title='Salvar versão (checkpoint)']").click

    expect(page).to have_text("Salvo", wait: 5)

    revision = wait_for_latest_checkpoint(note)
    expect(revision.ai_generated).to be(true)
  end

  it "preserves wikilink payloads when applying a grammar review suggestion" do
    uuid = SecureRandom.uuid
    note.head_revision.update!(content_markdown: "Texto com [[Pai|f:#{uuid}]] e erro.")

    allow(Ai::ReviewService).to receive(:enqueue).and_return(
      create(
        :ai_request,
        note_revision: note.head_revision,
        capability: "grammar_review",
        provider: "openai",
        requested_provider: "openai",
        model: "gpt-4o-mini",
        status: "succeeded",
        input_text: note.head_revision.content_markdown,
        output_text: "Texto corrigido com [[Pai traduzido|f:#{uuid}]] e ajuste.",
        metadata: {"language" => note.detected_language},
        completed_at: Time.current
      )
    )

    visit note_path(note.slug)

    choose_ai_option("Revisar gramática com IA")
    expect_ai_workspace(text: "[[Pai traduzido|f:#{uuid}]]")

    click_button "Aplicar"

    expect(editor_text).to include("[[Pai traduzido|f:#{uuid}]]")
  end

  it "preserves wikilink payloads when applying a rewrite suggestion" do
    uuid = SecureRandom.uuid
    note.head_revision.update!(content_markdown: "Bloco [[Referencia|b:#{uuid}]] para reescrever.")

    allow(Ai::ReviewService).to receive(:enqueue).and_return(
      create(
        :ai_request,
        note_revision: note.head_revision,
        capability: "rewrite",
        provider: "openai",
        requested_provider: "openai",
        model: "gpt-4o-mini",
        status: "succeeded",
        input_text: note.head_revision.content_markdown,
        output_text: "Bloco refinado com [[Referencia polida|b:#{uuid}]] para leitura.",
        metadata: {"language" => note.detected_language},
        completed_at: Time.current
      )
    )

    visit note_path(note.slug)

    choose_ai_option("Melhorar Markdown com IA")
    expect_ai_workspace(text: "[[Referencia polida|b:#{uuid}]]")

    click_button "Aplicar"

    expect(editor_text).to include("[[Referencia polida|b:#{uuid}]]")
  end

  it "renders queue cards with service, note title and model, and retries failed requests" do
    failed_request = create(
      :ai_request,
      note_revision: note.head_revision,
      capability: "grammar_review",
      provider: "openai",
      requested_provider: "openai",
      model: "gpt-4o-mini",
      status: "failed",
      error_message: "Falha temporaria"
    )

    allow(Ai::ReviewService).to receive(:retry_request!).and_call_original

    visit note_path(note.slug)

    expect(page).to have_css("[data-ai-review-target='queueDock']:not(.hidden)", wait: 5)
    within("[data-ai-review-target='queueDock']") do
      expect(page).to have_text(/revisar/i)
      expect(page).to have_text(note.title)
      expect(page).to have_text("gpt-4o-mini")
      find("[data-request-id='#{failed_request.id}'][data-queue-action='retry']").click
    end

    expect(failed_request.reload.status).to eq("queued")
    within("[data-ai-review-target='queueDock']") do
      expect(page).to have_text(/revisar/i)
      expect(page).to have_button("Cancelar", wait: 5)
    end
  end

  it "keeps a completed request in the queue until approval and lets the user reject it" do
    succeeded_request = create(
      :ai_request,
      note_revision: note.head_revision,
      capability: "grammar_review",
      provider: "openai",
      requested_provider: "openai",
      model: "gpt-4o-mini",
      status: "succeeded",
      output_text: "Texto corrigido.",
      completed_at: Time.current
    )

    visit note_path(note.slug)

    within("[data-ai-review-target='queueDock']") do
      expect(page).to have_text(/revisado/i)
      expect(page).to have_text(note.title)
      expect(page).to have_text("gpt-4o-mini")
      expect(page).to have_no_button("Cancelar")
      find("article", text: note.title).click
    end

    expect_ai_workspace(text: "Texto corrigido.")
    expect(page).to have_button("Recusar", wait: 5)
    expect(page).to have_button("Aplicar", wait: 5)
    expect(page).to have_css("[data-ai-review-target='queueDock'].hidden", visible: :all, wait: 5)

    click_button "Recusar"

    expect(page).to have_no_css("[data-request-id='#{succeeded_request.id}']", wait: 5)

    visit current_path

    expect(page).to have_no_css("[data-request-id='#{succeeded_request.id}']", wait: 5)
  end

  it "lets the user reject a created promise note and restores the original wikilink" do
    source_note = create(:note, :with_head_revision, title: "Nota Origem IA")
    promise_note = create(:note, title: "Meu novo camarada")
    Notes::DraftService.call(
      note: source_note,
      content: "Abrir [[Meu novo camarada|#{promise_note.id}]]",
      author: user
    )
    request_record = create(
      :ai_request,
      note_revision: source_note.head_revision,
      capability: "seed_note",
      provider: "openai",
      requested_provider: "openai",
      model: "gpt-4o-mini",
      status: "succeeded",
      metadata: {
        "language" => source_note.detected_language,
        "promise_source_note_id" => source_note.id,
        "promise_note_id" => promise_note.id,
        "promise_note_title" => promise_note.title
      },
      output_text: "# Meu novo camarada\n\nConteudo criado.",
      completed_at: Time.current
    )

    visit note_path(source_note.slug)

    within("[data-ai-review-target='queueDock']") do
      find("article", text: "Meu novo camarada").click
    end

    expect(page).to have_current_path(note_path(promise_note.slug), wait: 5)
    expect(page).to have_button("Recusar", wait: 5)
    click_button "Recusar"

    expect(page).to have_current_path(note_path(source_note.slug), wait: 5)

    expect(page).to have_no_css("[data-request-id='#{request_record.id}']", wait: 5)
    wait_until do
      promise_note_record = Note.find_by(id: promise_note.id)
      promise_note_record.nil? || promise_note_record.deleted?
    end
    restored_content = wait_until do
      source_note.reload.note_revisions.find_by(revision_kind: :draft)&.content_markdown == "Abrir [[Meu novo camarada]]"
    end
    expect(restored_content).to eq(true)
    expect(editor_text).to include("Abrir [[Meu novo camarada]]")

    visit note_path(source_note.slug)

    expect(page).to have_no_css("[data-request-id='#{request_record.id}']", wait: 5)
  end

  it "lets the user accept a created promise note from the queue before persisting the AI content" do
    source_note = create(:note, :with_head_revision, title: "Nota Origem Aceite")
    promise_note = create(:note, title: "Promessa Aceita", head_revision: nil)
    Notes::DraftService.call(
      note: source_note,
      content: "Abrir [[Promessa Aceita|#{promise_note.id}]]",
      author: user
    )
    request_record = create(
      :ai_request,
      note_revision: source_note.head_revision,
      capability: "seed_note",
      provider: "ollama",
      requested_provider: "ollama",
      model: "qwen2.5:1.5b",
      status: "succeeded",
      metadata: {
        "language" => source_note.detected_language,
        "requested_by_id" => user.id,
        "promise_source_note_id" => source_note.id,
        "promise_note_id" => promise_note.id,
        "promise_note_title" => promise_note.title
      },
      output_text: "# Promessa Aceita\n\nConteudo criado.",
      completed_at: Time.current
    )

    visit note_path(source_note.slug)

    within("[data-ai-review-target='queueDock']") do
      find("article", text: "Promessa Aceita").click
    end

    expect(page).to have_current_path(note_path(promise_note.slug), wait: 5)
    expect(page).to have_text("Conteudo criado.", wait: 5)
    expect(promise_note.reload.head_revision).to be_nil

    click_button "Aplicar"

    wait_until do
      promise_note.reload.head_revision&.content_markdown == "# Promessa Aceita\n\nConteudo criado."
    end
    expect(page).to have_no_css("[data-request-id='#{request_record.id}']", wait: 5)
  end

  it "preserves markdown markers when accepting a created promise note from the queue" do
    source_note = create(:note, :with_head_revision, title: "Nota Origem Markdown")
    promise_note = create(:note, title: "Promessa Markdown", head_revision: nil)
    Notes::DraftService.call(
      note: source_note,
      content: "Abrir [[Promessa Markdown|#{promise_note.id}]]",
      author: user
    )
    request_record = create(
      :ai_request,
      note_revision: source_note.head_revision,
      capability: "seed_note",
      provider: "ollama",
      requested_provider: "ollama",
      model: "qwen2.5:1.5b",
      status: "succeeded",
      metadata: {
        "language" => source_note.detected_language,
        "requested_by_id" => user.id,
        "promise_source_note_id" => source_note.id,
        "promise_note_id" => promise_note.id,
        "promise_note_title" => promise_note.title
      },
      output_text: "# Promessa Markdown\n\n- item 1\n- item 2\n\n**negrito**",
      completed_at: Time.current
    )

    visit note_path(source_note.slug)

    within("[data-ai-review-target='queueDock']") do
      find("article", text: "Promessa Markdown").click
    end

    expect(page).to have_current_path(note_path(promise_note.slug), wait: 5)
    click_button "Aplicar"

    wait_until do
      promise_note.reload.head_revision&.content_markdown == "# Promessa Markdown\n\n- item 1\n- item 2\n\n**negrito**"
    end
    expect(page).to have_no_css("[data-request-id='#{request_record.id}']", wait: 5)
  end

  it "shows markdown semantics in the seed note review UI" do
    source_note = create(:note, :with_head_revision, title: "Nota Origem UI Markdown")
    promise_note = create(:note, title: "Promessa UI Markdown", head_revision: nil)
    Notes::DraftService.call(
      note: source_note,
      content: "Abrir [[Promessa UI Markdown|#{promise_note.id}]]",
      author: user
    )
    create(
      :ai_request,
      note_revision: source_note.head_revision,
      capability: "seed_note",
      provider: "ollama",
      requested_provider: "ollama",
      model: "qwen2.5:1.5b",
      status: "succeeded",
      metadata: {
        "language" => source_note.detected_language,
        "requested_by_id" => user.id,
        "promise_source_note_id" => source_note.id,
        "promise_note_id" => promise_note.id,
        "promise_note_title" => promise_note.title
      },
      output_text: "# Promessa UI Markdown\n\n- item 1",
      completed_at: Time.current
    )

    visit note_path(source_note.slug)

    within("[data-ai-review-target='queueDock']") do
      find("article", text: "Promessa UI Markdown").click
    end

    expect(page).to have_current_path(note_path(promise_note.slug), wait: 5)
    expect(page).to have_css("[data-ai-review-target='proposalRawPane']:not(.hidden)", wait: 5)
    expect(page).to have_css("textarea[data-ai-review-target='correctedText']", visible: :visible, wait: 5)
    expect(page).to have_css("[data-ai-review-target='proposalDiff'].preview-prose h1", text: "Promessa UI Markdown", wait: 5)
    expect(page).to have_css("[data-ai-review-target='proposalDiff'].preview-prose li", text: "item 1", wait: 5)
  end

  it "hides queue cards while the AI workspace is open" do
    choose_ai_option("Revisar gramática com IA")

    expect_ai_workspace(text: "Texto corrigido pela IA.")
    expect(page).to have_css("[data-ai-review-target='queueDock'].hidden", visible: :all, wait: 5)
  end

  it "allows dismissing a failed request from the queue with X" do
    failed_request = create(
      :ai_request,
      note_revision: note.head_revision,
      capability: "grammar_review",
      provider: "openai",
      requested_provider: "openai",
      model: "gpt-4o-mini",
      status: "failed",
      error_message: "Falha temporaria"
    )

    visit note_path(note.slug)

    within("[data-ai-review-target='queueDock']") do
      find("button[title='Desistir'][data-request-id='#{failed_request.id}']").click
    end

    expect(page).to have_no_css("[data-request-id='#{failed_request.id}']", wait: 5)

    visit current_path

    expect(page).to have_no_css("[data-request-id='#{failed_request.id}']", wait: 5)
  end

  it "reorders active queue cards via drag and drop and persists priority" do
    low = create(
      :ai_request,
      note_revision: note.head_revision,
      capability: "grammar_review",
      provider: "openai",
      requested_provider: "openai",
      model: "model-low",
      status: "queued",
      queue_position: 1,
      metadata: {"language" => "pt-BR", "promise_note_title" => "Fila Baixa"}
    )
    mid = create(
      :ai_request,
      note_revision: note.head_revision,
      capability: "grammar_review",
      provider: "openai",
      requested_provider: "openai",
      model: "model-mid",
      status: "queued",
      queue_position: 2,
      metadata: {"language" => "pt-BR", "promise_note_title" => "Fila Media"}
    )
    high = create(
      :ai_request,
      note_revision: note.head_revision,
      capability: "grammar_review",
      provider: "openai",
      requested_provider: "openai",
      model: "model-high",
      status: "queued",
      queue_position: 3,
      metadata: {"language" => "pt-BR", "promise_note_title" => "Fila Alta"}
    )

    visit note_path(note.slug)

    expect(page).to have_css("[data-ai-review-target='queueDock']:not(.hidden)", wait: 5)
    expect(page).to have_css("[data-ai-review-target='queueDock'] article", count: 3, wait: 5)
    expect(queue_titles).to eq(["Fila Alta", "Fila Media", "Fila Baixa"])

    drag_queue_card_after(high.id, low.id)

    expect(page).to have_text("Fila Alta", wait: 5)
    expect(queue_titles).to eq(["Fila Media", "Fila Baixa", "Fila Alta"])

    expect(high.reload.queue_position).to eq(1)
    expect(low.reload.queue_position).to eq(2)
    expect(mid.reload.queue_position).to eq(3)
  end

  it "shows only a placeholder while dragging and ignores running items in manual reorder" do
    running = create(
      :ai_request,
      note_revision: note.head_revision,
      capability: "grammar_review",
      provider: "openai",
      requested_provider: "openai",
      model: "model-running",
      status: "running",
      queue_position: 9,
      metadata: {"language" => "pt-BR", "promise_note_title" => "Fila Rodando"}
    )
    queued = create(
      :ai_request,
      note_revision: note.head_revision,
      capability: "grammar_review",
      provider: "openai",
      requested_provider: "openai",
      model: "model-queued",
      status: "queued",
      queue_position: 1,
      metadata: {"language" => "pt-BR", "promise_note_title" => "Fila Pendente"}
    )

    visit note_path(note.slug)

    expect(page).to have_css("[data-ai-review-target='queueDock'] article", count: 2, wait: 5)
    expect(page).to have_css("[data-request-id='#{running.id}'][data-queue-reorderable='false']")
    expect(page).to have_css("[data-request-id='#{queued.id}'][data-queue-reorderable='true']")

    start_queue_drag(queued.id)
    drag_queue_over(running.id, position: :top)

    expect(page).to have_css("[data-queue-placeholder='true']", count: 1)
    expect(page).to have_css("[data-request-id='#{queued.id}'][style*='position: fixed']", visible: :all)
    expect(page).to have_css("[data-ai-review-target='queueDock'] [data-queue-card='true']", count: 2, visible: :all)

    finish_queue_drag(running.id, position: :top)

    expect(queue_titles).to include("Fila Rodando", "Fila Pendente")
    expect(queued.reload.queue_position).to eq(1)
  end

  it "keeps drag and drop working with scroll in the queue dock" do
    requests = 8.times.map do |index|
      create(
        :ai_request,
        note_revision: note.head_revision,
        capability: "grammar_review",
        provider: "openai",
        requested_provider: "openai",
        model: "model-#{index}",
        status: "queued",
        queue_position: index + 1,
        metadata: {"language" => "pt-BR", "promise_note_title" => "Fila #{index + 1}"}
      )
    end

    visit note_path(note.slug)

    expect(page).to have_css("[data-ai-review-target='queueDock'] article", count: 8, wait: 5)
    expect(queue_titles).to eq(["Fila 8", "Fila 7", "Fila 6", "Fila 5", "Fila 4", "Fila 3", "Fila 2", "Fila 1"])
    page.execute_script(<<~JS)
      const dock = document.querySelector("[data-ai-review-target='queueDock']")
      dock.scrollTop = dock.scrollHeight
    JS

    drag_queue_card_after(requests.first.id, requests[2].id)

    expect(queue_titles).to eq(["Fila 8", "Fila 7", "Fila 6", "Fila 5", "Fila 4", "Fila 3", "Fila 1", "Fila 2"])
    wait_for_request_queue_position(requests.first, 2)
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

    choose_ai_option("Revisar gramática com IA")

    expect(page).to have_no_css("[data-ai-review-target='workspace']:not(.hidden)", wait: 2)
    expect(page).to have_text("qwen2:1.5b")
  end

  it "creates a translated sibling note when accepting a translation result" do
    uuid = SecureRandom.uuid
    source_content = "# Resumo\n\nVeja [[Pai|f:#{uuid}]]."
    note.head_revision.update!(content_markdown: source_content)
    translated_request = create(
      :ai_request,
      note_revision: note.head_revision,
      capability: "translate",
      provider: "ollama",
      requested_provider: "ollama",
      model: "qwen2:1.5b",
      status: "succeeded",
      input_text: source_content,
      output_text: "# Clinical Summary\n\nTranslated [[Father|f:#{uuid}]] content.",
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
      content: "# Clinical Summary\n\nTranslated [[Father|f:#{uuid}]] content.",
      target_language: "en-US",
      title: "Clinical Summary (Polished)",
      author: user
    ).and_return(translated_note)

    find("button[title='Traduzir com IA']").click
    expect(page).to have_css("[data-ai-review-target='requestMenu']:not(.hidden)", wait: 5)
    page.execute_script(<<~JS)
      const languageSelect = document.querySelector("[data-ai-review-translate-language]")
      const modelSelect = document.querySelector("[data-ai-review-translate-model]")
      languageSelect.value = "en-US"
      languageSelect.dispatchEvent(new Event("change", { bubbles: true }))
      modelSelect.selectedIndex = Array.from(modelSelect.options).findIndex((option) => option.textContent.includes("Automatico · Ollama"))
      modelSelect.dispatchEvent(new Event("change", { bubbles: true }))
    JS
    click_button "Traduzir"

    expect_ai_workspace(text: "Clinical Summary")
    expect(page).to have_field("Titulo da nova nota", with: "Clinical Summary")
    fill_in "Titulo da nova nota", with: "Clinical Summary (Polished)"
    click_button "Criar nota traduzida"

    expect(page).to have_current_path(note_path(translated_note.slug), wait: 5)
  end

  it "shows the fallback when AI is not configured" do
    ENV["AI_ENABLED"] = "false"
    visit note_path(note.slug)

    find("button[title='Melhorar Markdown com IA']").click

    expect_ai_workspace(text: "IA não configurada")
  end

  it "keeps the preview visible while a request is waiting for retry" do
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

    choose_ai_option("Revisar gramática com IA")

    expect(page).to have_no_css("[data-ai-review-target='workspace']:not(.hidden)", wait: 2)
    expect(page).to have_css("[data-request-id='#{request.id}']", wait: 5)
    expect_ai_workspace(text: "Texto corrigido pela IA.", wait: 8)
    expect(page).to have_css(".cm-ai-diff-deleted", minimum: 1, wait: 8)
  end

  it "cancels the in-flight request from the queue card" do
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

    choose_ai_option("Revisar gramática com IA")
    wait_until(timeout: 10) { request.present? }

    expect(page).to have_css("[data-request-id='#{request.id}']", wait: 5)
    find("[data-request-id='#{request.id}'][data-queue-action='cancel']", wait: 5).click

    expect(page).to have_no_css("[data-request-id='#{request.id}']", wait: 5)
    wait_until { request.reload.status == "canceled" }
  end

  it "ignores a late succeeded update after canceling the in-flight request" do
    request = nil
    original_text = editor_text

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

    choose_ai_option("Revisar gramática com IA")
    wait_until(timeout: 10) { request.present? }

    expect(page).to have_css("[data-request-id='#{request.id}']", wait: 5)
    find("[data-request-id='#{request.id}'][data-queue-action='cancel']", wait: 5).click

    expect(page).to have_no_css("[data-request-id='#{request.id}']", wait: 5)
    wait_until { request.reload.status == "canceled" }

    request.update!(
      status: "succeeded",
      output_text: "Texto tardio da IA.",
      completed_at: Time.current,
      next_retry_at: nil,
      error_message: nil,
      last_error_kind: nil
    )

    dispatch_request_update(request)

    expect(page).to have_no_css("[data-ai-review-target='workspace']:not(.hidden)", wait: 2)
    expect(page).to have_no_text("Texto tardio da IA.")
    expect(page).to have_no_css("[data-request-id='#{request.id}']", wait: 2)
    expect(editor_text).to eq(original_text)
  end

  it "shows manual edits highlighted in yellow after editing the proposal" do
    choose_ai_option("Melhorar Markdown com IA")

    expect_ai_workspace(text: "Texto corrigido pela IA.")
    replace_ai_suggested_text("Texto corrigido manualmente pela IA.")

    expect(page).to have_css("[data-ai-review-target='proposalDiff']", text: "manualmente", wait: 5)
  end

  it "keeps only the three core AI actions in the toolbar" do
    expect(page).to have_button("Melhorar Markdown com IA")
    expect(page).to have_button("Revisar gramática com IA")
    expect(page).to have_button("Traduzir com IA")
    expect(page).to have_no_button("Sugestão com IA")
    expect(page).to have_no_button("Reescrever com IA")
  end

  it "lets the user choose translation language and model independently" do
    captured_enqueue = nil

    allow(Ai::ReviewService).to receive(:status).and_return(
      {
        enabled: true,
        provider: "ollama",
        model: "qwen2:1.5b",
        available_providers: ["ollama", "openai"],
        provider_options: [
          {
            name: "ollama",
            label: "Ollama",
            default_model: "qwen2:1.5b",
            models: ["qwen2:1.5b", "qwen2.5:3b"],
            selected: true,
            selected_model: "qwen2:1.5b"
          },
          {
            name: "openai",
            label: "OpenAI",
            default_model: "gpt-4o-mini",
            models: ["gpt-4o-mini"],
            selected: false,
            selected_model: "gpt-4o-mini"
          }
        ]
      }
    )

    allow(Ai::ReviewService).to receive(:enqueue).and_wrap_original do |_original, **args|
      captured_enqueue = args
      create(
        :ai_request,
        note_revision: note.head_revision,
        capability: "translate",
        provider: "openai",
        requested_provider: "openai",
        model: "gpt-4o-mini",
        status: "succeeded",
        input_text: note.head_revision.content_markdown,
        output_text: "# Resumen\n\nContenido traducido.",
        metadata: {"language" => note.detected_language, "target_language" => "es"},
        completed_at: Time.current
      )
    end

    visit note_path(note.slug)

    find("button[title='Traduzir com IA']").click
    expect(page).to have_css("[data-ai-review-target='requestMenu']:not(.hidden)", wait: 5)
    expect(page).to have_css("[data-ai-review-translate-language]", wait: 5)
    expect(page).to have_css("[data-ai-review-translate-model]", wait: 5)
    expect(page).to have_select("Modelo", with_options: ["Automatico · Ollama", "Ollama · qwen2:1.5b", "Ollama · qwen2.5:3b", "Automatico · OpenAI", "OpenAI · gpt-4o-mini"])
    expect(page).to have_no_select("Modelo", with_options: ["Portugues · Automatico · Ollama"])

    page.execute_script(<<~JS)
      const languageSelect = document.querySelector("[data-ai-review-translate-language]")
      const modelSelect = document.querySelector("[data-ai-review-translate-model]")
      languageSelect.value = "es"
      languageSelect.dispatchEvent(new Event("change", { bubbles: true }))
      modelSelect.selectedIndex = Array.from(modelSelect.options).findIndex((option) => option.textContent.includes("OpenAI · gpt-4o-mini"))
      modelSelect.dispatchEvent(new Event("change", { bubbles: true }))
    JS
    click_button "Traduzir"

    expect(captured_enqueue).to include(
      capability: "translate",
      target_language: "es",
      model_name: "gpt-4o-mini",
      provider_name: "openai"
    )
    expect_ai_workspace(text: "Resumen")
  end

  it "shows recent AI executions in the history dialog" do
    other_note = create(:note, :with_head_revision, title: "Nota Global Historico")

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

    create(
      :ai_request,
      note_revision: other_note.head_revision,
      capability: "translate",
      provider: "openai",
      requested_provider: "openai",
      model: "gpt-4o-mini",
      status: "succeeded",
      completed_at: Time.current
    )

    find("button[title='Histórico de IA']").click
    expect(page).to have_css("dialog[open]", text: "Histórico de IA", wait: 5)
    expect(page).to have_text("Revisao gramatical", wait: 5)
    expect(page).to have_text("Melhoria de Markdown", wait: 5)
    expect(page).to have_text("Traducao", wait: 5)
    expect(page).to have_text("Nota Global Historico", wait: 5)
    expect(page).to have_text("Concluida", wait: 5)
    expect(page).to have_text("Falhou", wait: 5)
    expect(page).to have_text("Falha remota", wait: 5)

    click_button "Falhas"
    within("dialog[open]") do
      expect(page).to have_text("Falha remota", wait: 5)
      expect(page).to have_no_text("Revisao gramatical", wait: 5)
    end

    click_button "Concluídas"
    within("dialog[open]") do
      expect(page).to have_text("Revisao gramatical", wait: 5)
      expect(page).to have_no_text("Falha remota", wait: 5)
    end
  end

  it "keeps older applicable results visible in the shell history" do
    applicable_note = create(:note, :with_head_revision, title: "Nota Aplicavel Antiga")
    create(
      :ai_request,
      note_revision: applicable_note.head_revision,
      capability: "rewrite",
      provider: "openai",
      requested_provider: "openai",
      model: "gpt-4o-mini",
      status: "succeeded",
      output_text: "Texto revisado antigo.",
      created_at: 2.days.ago,
      completed_at: 2.days.ago
    )

    24.times do |index|
      recent_note = create(:note, :with_head_revision, title: "Historico Recente #{index}")
      create(
        :ai_request,
        note_revision: recent_note.head_revision,
        capability: "grammar_review",
        provider: "openai",
        requested_provider: "openai",
        model: "gpt-4o-mini",
        status: "failed",
        error_message: "Falha #{index}",
        created_at: (24 - index).minutes.ago
      )
    end

    find("button[title='Histórico de IA']").click

    within("[data-ai-review-target='historyList']") do
      expect(page).to have_text("Nota Aplicavel Antiga", wait: 5)
      expect(page).to have_text("Aplicavel", wait: 5)
    end

    click_button "Aplicáveis"
    within("dialog[open]") do
      expect(page).to have_text("Nota Aplicavel Antiga", wait: 5)
      expect(page).to have_no_text("Historico Recente 0", wait: 5)
    end
  end

  it "filters queued items from the global AI history" do
    other_note = create(:note, :with_head_revision, title: "Fila Global")
    create(
      :ai_request,
      note_revision: other_note.head_revision,
      capability: "seed_note",
      provider: "ollama",
      requested_provider: "ollama",
      model: "qwen2.5:1.5b",
      status: "queued",
      metadata: {
        "language" => "pt-BR",
        "promise_note_id" => create(:note, title: "Fila Global").id,
        "promise_note_title" => "Fila Global"
      }
    )

    find("button[title='Histórico de IA']").click

    expect(page).to have_css("dialog[open]", text: "Histórico de IA", wait: 5)
    click_button "Na fila"
    expect(page).to have_text("Fila Global", wait: 5)
    expect(page).to have_text("Na fila", wait: 5)
  end

  it "closes the AI history window when clicking outside it" do
    find("button[title='Histórico de IA']").click

    expect(page).to have_css("dialog[open]", text: "Histórico de IA", wait: 5)

    page.find("body").click(x: 5, y: 5)

    expect(page).to have_no_css("dialog[open]", wait: 5)
  end

  it "opens a succeeded seed note from the shell history" do
    promise_note = create(:note, title: "Historico Promessa")
    request_record = create(
      :ai_request,
      note_revision: head_revision,
      capability: "seed_note",
      provider: "ollama",
      requested_provider: "ollama",
      model: "qwen2.5:1.5b",
      status: "succeeded",
      completed_at: Time.current,
      output_text: "# Historico Promessa\n\nConteudo criado.",
      metadata: {
        "language" => note.detected_language,
        "promise_note_id" => promise_note.id,
        "promise_note_title" => promise_note.title
      }
    )

    find("button[title='Histórico de IA']").click
    within("[data-ai-review-target='historyList']") do
      find("[data-request-id='#{request_record.id}']", text: "Historico Promessa").click
    end

    expect(page).to have_current_path(note_path(promise_note.slug), wait: 5)
    expect(page).to have_button("Recusar", wait: 5)
    expect(page).to have_button("Aplicar", wait: 5)
  end

  it "keeps a reopened result visible after newer activity pushes recent history forward" do
    reopened_note = create(:note, :with_head_revision, title: "Nota Reaberta")
    request_record = create(
      :ai_request,
      note_revision: reopened_note.head_revision,
      capability: "grammar_review",
      provider: "openai",
      requested_provider: "openai",
      model: "gpt-4o-mini",
      status: "succeeded",
      input_text: "Texto antigo com erro.",
      output_text: "Texto antigo corrigido.",
      created_at: 2.days.ago,
      completed_at: 2.days.ago,
      metadata: {
        "language" => "pt-BR",
        "accepted_at" => 1.day.ago.iso8601
      }
    )

    10.times do |index|
      recent_note = create(:note, :with_head_revision, title: "Janela Inicial #{index}")
      create(
        :ai_request,
        note_revision: recent_note.head_revision,
        capability: "rewrite",
        provider: "openai",
        requested_provider: "openai",
        model: "gpt-4o-mini",
        status: "failed",
        error_message: "Falha inicial #{index}",
        created_at: (10 - index).minutes.ago
      )
    end

    find("button[title='Histórico de IA']").click
    within("[data-ai-review-target='historyList']") do
      find("[data-request-id='#{request_record.id}']", text: "Nota Reaberta").click
    end
    expect_ai_workspace(text: "Texto antigo corrigido.", wait: 5)

    25.times do |index|
      newer_note = create(:note, :with_head_revision, title: "Empurra Historico #{index}")
      create(
        :ai_request,
        note_revision: newer_note.head_revision,
        capability: "grammar_review",
        provider: "openai",
        requested_provider: "openai",
        model: "gpt-4o-mini",
        status: "failed",
        error_message: "Falha nova #{index}",
        created_at: index.seconds.ago
      )
    end

    find("button[title='Histórico de IA']").click unless page.has_css?("dialog[open]", wait: 1)
    within("dialog[open]") do
      find("button[title='Atualizar histórico de IA']").click
      expect(page).to have_text("Nota Reaberta", wait: 5)
      expect(page).to have_text("Reaberta", wait: 5)
    end

    click_button "Reabertas"
    within("dialog[open]") do
      expect(page).to have_text("Nota Reaberta", wait: 5)
      expect(page).to have_no_text("Empurra Historico 0", wait: 5)
    end
  end

  it "opens a succeeded rewrite on the source note instead of the currently open note" do
    other_note = create(:note, :with_head_revision, title: "Nota Origem Review")
    other_note.head_revision.update!(content_markdown: "Texto original da outra nota.")
    request_record = create(
      :ai_request,
      note_revision: other_note.head_revision,
      capability: "rewrite",
      provider: "openai",
      requested_provider: "openai",
      model: "gpt-4o-mini",
      status: "succeeded",
      completed_at: Time.current,
      input_text: "Texto original da outra nota.",
      output_text: "Texto revisado da outra nota."
    )

    find("button[title='Histórico de IA']").click
    within("[data-ai-review-target='historyList']") do
      find("[data-request-id='#{request_record.id}']", text: "Nota Origem Review").click
    end

    expect(page).to have_current_path(note_path(other_note.slug), wait: 5)
    expect_ai_workspace(text: "Texto revisado da outra nota.", wait: 5)
  end

  it "opens a succeeded grammar review on the source note instead of the currently open note" do
    other_note = create(:note, :with_head_revision, title: "Nota Origem Gramatica")
    other_note.head_revision.update!(content_markdown: "Texto original com erro da outra nota.")
    request_record = create(
      :ai_request,
      note_revision: other_note.head_revision,
      capability: "grammar_review",
      provider: "openai",
      requested_provider: "openai",
      model: "gpt-4o-mini",
      status: "succeeded",
      completed_at: Time.current,
      input_text: "Texto original com erro da outra nota.",
      output_text: "Texto original corrigido da outra nota."
    )

    find("button[title='Histórico de IA']").click
    within("[data-ai-review-target='historyList']") do
      find("[data-request-id='#{request_record.id}']", text: "Nota Origem Gramatica").click
    end

    expect(page).to have_current_path(note_path(other_note.slug), wait: 5)
    expect_ai_workspace(text: "Texto original corrigido da outra nota.", wait: 5)
  end

  it "opens a succeeded translation on the translated note when it already exists" do
    other_note = create(:note, :with_head_revision, title: "Nota Origem Traducao")
    translated_note = create(:note, :with_head_revision, title: "Translated Existing", detected_language: "en-US")
    request_record = create(
      :ai_request,
      note_revision: other_note.head_revision,
      capability: "translate",
      provider: "openai",
      requested_provider: "openai",
      model: "gpt-4o-mini",
      status: "succeeded",
      completed_at: Time.current,
      input_text: "# Nota Origem Traducao\n\nTexto base.",
      output_text: "# Translated Existing\n\nTranslated text.",
      metadata: {
        "language" => "pt-BR",
        "target_language" => "en-US",
        "translated_note_id" => translated_note.id
      }
    )

    find("button[title='Histórico de IA']").click
    within("[data-ai-review-target='historyList']") do
      find("[data-request-id='#{request_record.id}']", text: "Nota Origem Traducao").click
    end

    expect(page).to have_current_path(note_path(translated_note.slug), wait: 5)
    expect(page).to have_field(type: "text", with: "Translated Existing", wait: 5)
    expect(page).to have_no_css("[data-ai-review-target='workspace']:not(.hidden)", wait: 2)
  end

  it "refreshes queue and shell history via fallback polling when realtime is unavailable" do
    queued_request = create(
      :ai_request,
      note_revision: head_revision,
      capability: "seed_note",
      provider: "ollama",
      requested_provider: "ollama",
      model: "qwen2.5:1.5b",
      status: "queued",
      metadata: {
        "language" => note.detected_language,
        "promise_note_id" => create(:note, title: "Fila Fallback").id,
        "promise_note_title" => "Fila Fallback"
      }
    )

    visit note_path(note.slug)
    force_ai_queue_fallback_polling
    refresh_ai_queue_now

    expect(page).to have_css("[data-ai-review-target='queueDock']:not(.hidden)", wait: 5)
    within("[data-ai-review-target='queueDock']") do
      expect(page).to have_text(/criar/i, wait: 5)
      expect(page).to have_text("Fila Fallback", wait: 5)
    end

    queued_request.update!(
      status: "succeeded",
      completed_at: Time.current,
      output_text: "# Fila Fallback\n\nConteudo inicial."
    )

    within("[data-ai-review-target='queueDock']") do
      expect(page).to have_text(/criado/i, wait: 6)
    end

    find("button[title='Histórico de IA']").click
    expect(page).to have_text("Fila Fallback", wait: 6)
    expect(page).to have_text("Concluida", wait: 6)
  end
end
