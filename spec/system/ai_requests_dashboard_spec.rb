require "rails_helper"

RSpec.describe "AI requests dashboard", type: :system do
  let!(:user) { create(:user) }
  let!(:note) { create(:note, :with_head_revision, title: "Painel de IA") }
  let!(:head_revision) { note.reload.head_revision }

  before do
    create(
      :ai_request,
      note_revision: head_revision,
      capability: "rewrite",
      provider: "openai",
      requested_provider: "openai",
      model: "gpt-4o-mini",
      status: "failed",
      error_message: "Timeout remoto"
    )

    sign_in_via_ui(user)
  end

  it "opens the global AI operations page from the graph" do
    visit graph_path

    click_link "IA Ops"

    expect(page).to have_text("Operações de IA", wait: 5)
    expect(page).to have_text("Painel de IA", wait: 5)
    expect(page).to have_text("Timeout remoto", wait: 5)
    expect(page).to have_text(/Tempo real .* polling pausado|Tempo real .* fallback polling/, wait: 5)
  end

  it "filters the dashboard by failed requests" do
    create(
      :ai_request,
      note_revision: head_revision,
      capability: "grammar_review",
      provider: "openai",
      requested_provider: "openai",
      model: "gpt-4o-mini",
      status: "succeeded",
      output_text: "OK"
    )

    visit ai_requests_dashboard_path

    click_link "Falhas"

    expect(page).to have_text("Timeout remoto", wait: 5)
    expect(page).to have_no_text("OK", wait: 5)
  end

  it "filters the dashboard by provider and model and shows aggregate metrics" do
    create(
      :ai_request,
      note_revision: head_revision,
      capability: "grammar_review",
      provider: "anthropic",
      requested_provider: "anthropic",
      model: "claude-3-5-sonnet-latest",
      status: "succeeded",
      output_text: "Saída Anthropic",
      started_at: 3.seconds.ago,
      completed_at: 1.second.ago
    )

    visit ai_requests_dashboard_path

    select "openai", from: "Provider"
    select "gpt-4o-mini", from: "Modelo"
    click_button "Aplicar"

    expect(page).to have_text("Timeout remoto", wait: 5)
    expect(page).to have_no_text("Saída Anthropic", wait: 5)
    expect(page).to have_text("LATÊNCIA MÉDIA", wait: 5)
    expect(page).to have_text("FALHAS TRANSITÓRIAS", wait: 5)
  end

  it "sorts by attempts and highlights stuck requests" do
    create(
      :ai_request,
      note_revision: head_revision,
      capability: "grammar_review",
      provider: "openai",
      requested_provider: "openai",
      model: "gpt-4o-mini",
      status: "retrying",
      attempts_count: 1,
      next_retry_at: 3.minutes.ago,
      error_message: "Retry atrasado"
    )

    visit ai_requests_dashboard_path

    select "Mais tentativas", from: "Ordenar por"
    click_button "Aplicar"

    expect(page).to have_text("Retry atrasado", wait: 5)
    expect(page).to have_text("PRESAS", wait: 5)
    expect(page).to have_text(/Requests presas exigem intervenção/i, wait: 5)
    expect(page).to have_css(".nm-ai-ops__badge--stuck", text: "Retry atrasado", wait: 5)
  end

  it "shows operational alerts when failures and retries accumulate" do
    create(:ai_request, note_revision: head_revision, status: "failed", error_message: "Falha 1", last_error_kind: "transient")
    create(:ai_request, note_revision: head_revision, status: "failed", error_message: "Falha 2", last_error_kind: "transient")
    create(:ai_request, note_revision: head_revision, status: "failed", error_message: "Falha 3")
    create(:ai_request, note_revision: head_revision, status: "retrying", next_retry_at: 10.seconds.from_now, last_error_kind: "transient")

    visit ai_requests_dashboard_path

    expect(page).to have_css(".nm-ai-ops__hero-alert", text: /Acúmulo de falhas visíveis/i, wait: 5)
    expect(page).to have_text(/Acúmulo de falhas visíveis/i, wait: 5)
    expect(page).to have_text(/Retry congestionado/i, wait: 5)
    expect(page).to have_button("Reprocessar falhas", wait: 5)
    expect(page).to have_button("Cancelar retries", wait: 5)
  end

  it "uses the alert CTA to focus incident requests" do
    create(
      :ai_request,
      note_revision: head_revision,
      capability: "grammar_review",
      provider: "openai",
      requested_provider: "openai",
      model: "gpt-4o-mini",
      status: "retrying",
      attempts_count: 1,
      next_retry_at: 3.minutes.ago,
      error_message: "Retry atrasado"
    )

    visit ai_requests_dashboard_path

    expect(page).to have_text(/Incidente principal/i, wait: 5)
    click_link "Abrir incidentes"

    expect(page).to have_current_path(ai_requests_dashboard_path(sort: "retry_due_first"), ignore_query: false, wait: 5)
    expect(page).to have_text("Retry atrasado", wait: 5)
  end

  it "renders the stuck incident as the top highlighted incident" do
    create(
      :ai_request,
      note_revision: head_revision,
      capability: "grammar_review",
      provider: "openai",
      requested_provider: "openai",
      model: "gpt-4o-mini",
      status: "retrying",
      attempts_count: 1,
      next_retry_at: 3.minutes.ago,
      error_message: "Retry atrasado"
    )
    create(:ai_request, note_revision: head_revision, status: "failed", error_message: "Falha 1", last_error_kind: "transient")
    create(:ai_request, note_revision: head_revision, status: "failed", error_message: "Falha 2", last_error_kind: "transient")
    create(:ai_request, note_revision: head_revision, status: "failed", error_message: "Falha 3")

    visit ai_requests_dashboard_path

    expect(page).to have_css(".nm-ai-ops__hero-alert", text: /Requests presas exigem intervenção/i, wait: 5)
    expect(page).to have_text(/Acúmulo de falhas visíveis/i, wait: 5)
  end

  it "retries failed requests from the alert CTA" do
    create(:ai_request, note_revision: head_revision, status: "failed", error_message: "Falha 1", last_error_kind: "transient")
    create(:ai_request, note_revision: head_revision, status: "failed", error_message: "Falha 2", last_error_kind: "transient")
    create(:ai_request, note_revision: head_revision, status: "failed", error_message: "Falha 3")

    visit ai_requests_dashboard_path

    click_button "Reprocessar falhas"

    expect(page).to have_text("4 request(s) de IA reenfileirada(s).", wait: 5)
    expect(page).to have_text("QUEUED", wait: 5)
  end

  it "shows auto refresh as active when there are visible in-flight requests" do
    create(
      :ai_request,
      note_revision: head_revision,
      capability: "grammar_review",
      provider: "openai",
      requested_provider: "openai",
      model: "gpt-4o-mini",
      status: "running",
      started_at: 30.seconds.ago
    )

    visit ai_requests_dashboard_path

    expect(page).to have_text(/Tempo real .* refresh de apoio em|Tempo real .* fallback polling em/, wait: 5)
    expect(page).to have_css(".nm-ai-ops__auto-refresh-dot.is-live", wait: 5)
  end

  it "reprocesses a failed request from the dashboard" do
    visit ai_requests_dashboard_path

    click_button "Reprocessar"

    expect(page).to have_text("Request de IA reenfileirada.", wait: 5)
    expect(page).to have_text("QUEUED", wait: 5)
    expect(head_revision.ai_requests.recent_first.first.reload.status).to eq("queued")
  end

  it "cancels an active request from the dashboard" do
    active_request = create(
      :ai_request,
      note_revision: head_revision,
      capability: "grammar_review",
      provider: "openai",
      requested_provider: "openai",
      model: "gpt-4o-mini",
      status: "retrying",
      next_retry_at: 30.seconds.from_now
    )

    visit ai_requests_dashboard_path(status: "retrying")

    click_button "Cancelar"

    expect(page).to have_text("Request de IA cancelada.", wait: 5)
    expect(page).to have_text("CANCELED", wait: 5)
    expect(active_request.reload.status).to eq("canceled")
  end

  it "retries visible failed requests in batch from the dashboard" do
    create(:ai_request, note_revision: head_revision, status: "failed", error_message: "Falha em lote 1")
    create(:ai_request, note_revision: head_revision, status: "failed", error_message: "Falha em lote 2")

    visit ai_requests_dashboard_path(status: "failed")

    click_button "Reprocessar falhas visíveis"

    expect(page).to have_text("QUEUED", wait: 5)
    expect(page).to have_no_text("Falha em lote 1", wait: 5)
    expect(page).to have_no_text("Falha em lote 2", wait: 5)
  end

  it "cancels visible active requests in batch from the dashboard" do
    create(:ai_request, note_revision: head_revision, status: "retrying", next_retry_at: 15.seconds.from_now)
    create(:ai_request, note_revision: head_revision, status: "retrying", next_retry_at: 20.seconds.from_now)

    visit ai_requests_dashboard_path(status: "retrying")

    click_button "Cancelar ativas visíveis"

    expect(page).to have_text("2 request(s) de IA cancelada(s).", wait: 5)
    expect(page).to have_text("CANCELED", wait: 5)
  end
end
