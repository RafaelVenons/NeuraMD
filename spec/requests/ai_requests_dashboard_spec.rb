require "rails_helper"

RSpec.describe "AI requests dashboard", type: :request do
  let(:user) { create(:user) }
  let(:note) { create(:note, :with_head_revision, title: "Nota global") }

  before { sign_in user }

  it "renders recent requests across notes" do
    create(
      :ai_request,
      note_revision: note.head_revision,
      capability: "grammar_review",
      provider: "openai",
      requested_provider: "openai",
      model: "gpt-4o-mini",
      status: "failed",
      error_message: "Falha remota"
    )

    get ai_requests_dashboard_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Operações de IA")
    expect(response.body).to include("Nota global")
    expect(response.body).to include("Falha remota")
    expect(response.body).to include("Tempo real indisponível • polling pausado")
    expect(response.body).to include("turbo-cable-stream-source")
  end

  it "filters requests by status" do
    create(:ai_request, note_revision: note.head_revision, status: "failed", error_message: "Falha isolada")
    create(:ai_request, note_revision: note.head_revision, status: "succeeded", output_text: "Sucesso isolado")

    get ai_requests_dashboard_path, params: { status: "failed" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Falha isolada")
    expect(response.body).not_to include("Sucesso isolado")
  end

  it "filters requests by provider and model and keeps aggregate metrics visible" do
    create(
      :ai_request,
      note_revision: note.head_revision,
      status: "failed",
      provider: "openai",
      model: "gpt-4o-mini",
      error_message: "Falha OpenAI",
      last_error_kind: "transient",
      started_at: 4.seconds.ago,
      completed_at: 2.seconds.ago
    )
    create(
      :ai_request,
      note_revision: note.head_revision,
      status: "succeeded",
      provider: "anthropic",
      model: "claude-3-5-sonnet-latest",
      output_text: "OK",
      started_at: 3.seconds.ago,
      completed_at: 1.second.ago
    )

    get ai_requests_dashboard_path, params: { provider: "openai", model: "gpt-4o-mini" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Falha OpenAI")
    expect(response.body).not_to include("OK")
    expect(response.body).to include("Latência média")
    expect(response.body).to include("Falhas transitórias")
  end

  it "sorts requests by attempts and highlights stuck requests in the summary" do
    create(
      :ai_request,
      note_revision: note.head_revision,
      status: "retrying",
      attempts_count: 1,
      next_retry_at: 3.minutes.ago,
      error_message: "Atrasada"
    )
    create(
      :ai_request,
      note_revision: note.head_revision,
      status: "failed",
      attempts_count: 4,
      error_message: "Mais tentativas"
    )

    get ai_requests_dashboard_path, params: { sort: "attempts_desc" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Presas")
    expect(response.body).to include("Retry atrasado")
    expect(response.body).to include("Requests presas exigem intervenção")
    expect(response.body.index("Mais tentativas")).to be < response.body.index("Atrasada")
  end

  it "shows operational alerts when failures and retries accumulate" do
    create(:ai_request, note_revision: note.head_revision, status: "failed", error_message: "Falha 1", last_error_kind: "transient")
    create(:ai_request, note_revision: note.head_revision, status: "failed", error_message: "Falha 2", last_error_kind: "transient")
    create(:ai_request, note_revision: note.head_revision, status: "failed", error_message: "Falha 3")
    create(:ai_request, note_revision: note.head_revision, status: "retrying", next_retry_at: 10.seconds.from_now, last_error_kind: "transient")

    get ai_requests_dashboard_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Acúmulo de falhas visíveis")
    expect(response.body).to include("Retry congestionado")
    expect(response.body).to include("Incidente principal")
    expect(response.body).to include("Filtrar falhas")
    expect(response.body).to include("Reprocessar falhas")
    expect(response.body).to include("Filtrar retries")
    expect(response.body).to include("Cancelar retries")
  end

  it "adds contextual actions to the stuck alert" do
    create(:ai_request, note_revision: note.head_revision, status: "retrying", next_retry_at: 3.minutes.ago)

    get ai_requests_dashboard_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Requests presas exigem intervenção")
    expect(response.body).to include("Incidente principal")
    expect(response.body).to include("Abrir incidentes")
    expect(response.body).to include(%(href="#{ai_requests_dashboard_path(sort: "retry_due_first")}"))
  end

  it "prioritizes the stuck incident ahead of secondary alerts" do
    create(:ai_request, note_revision: note.head_revision, status: "retrying", next_retry_at: 3.minutes.ago)
    create(:ai_request, note_revision: note.head_revision, status: "failed", error_message: "Falha 1", last_error_kind: "transient")
    create(:ai_request, note_revision: note.head_revision, status: "failed", error_message: "Falha 2", last_error_kind: "transient")
    create(:ai_request, note_revision: note.head_revision, status: "failed", error_message: "Falha 3")

    get ai_requests_dashboard_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(aria-label="Incidente principal"))
    expect(response.body.index("Requests presas exigem intervenção")).to be < response.body.index("Acúmulo de falhas visíveis")
  end

  it "shows auto refresh as active when visible requests are still in progress" do
    create(:ai_request, note_revision: note.head_revision, status: "running", started_at: 1.minute.ago)

    get ai_requests_dashboard_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Tempo real indisponível • fallback polling em 10s")
    expect(response.body).to include("data-ai-ops-refresh-active-count-value=\"1\"")
  end

  it "renders only the dashboard fragment for partial refresh requests" do
    create(:ai_request, note_revision: note.head_revision, status: "running", started_at: 1.minute.ago)

    get ai_requests_dashboard_path, params: { partial: "1" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("data-ai-ops-refresh-fragment")
    expect(response.body).to include("Tempo real indisponível • fallback polling em 10s")
    expect(response.body).not_to include("<html")
    expect(response.body).not_to include("Operações de IA")
  end

  it "re-enqueues a failed request" do
    request_record = create(
      :ai_request,
      note_revision: note.head_revision,
      status: "failed",
      attempts_count: 3,
      error_message: "Falha antiga",
      output_text: "Resposta antiga"
    )

    expect {
      post retry_ai_request_path(request_record)
    }.to have_enqueued_job(Ai::ReviewJob)

    expect(response).to redirect_to(ai_requests_dashboard_path(sort: "newest"))

    request_record.reload
    expect(request_record.status).to eq("queued")
    expect(request_record.attempts_count).to eq(0)
    expect(request_record.error_message).to be_nil
    expect(request_record.output_text).to be_nil
  end

  it "preserves provider and model filters while re-enqueuing a request" do
    request_record = create(
      :ai_request,
      note_revision: note.head_revision,
      status: "failed",
      provider: "openai",
      model: "gpt-4o-mini"
    )

    post retry_ai_request_path(request_record), params: { provider: "openai", model: "gpt-4o-mini" }

    expect(response).to redirect_to(ai_requests_dashboard_path(provider: "openai", model: "gpt-4o-mini", sort: "newest"))
  end

  it "preserves sort and scope filters while canceling a request" do
    request_record = create(
      :ai_request,
      note_revision: note.head_revision,
      status: "retrying",
      provider: "openai",
      model: "gpt-4o-mini",
      next_retry_at: 10.seconds.from_now
    )

    delete ai_request_dashboard_path(request_record), params: { provider: "openai", model: "gpt-4o-mini", sort: "retry_due_first" }

    expect(response).to redirect_to(ai_requests_dashboard_path(status: "canceled", provider: "openai", model: "gpt-4o-mini", sort: "retry_due_first"))
  end

  it "cancels an active request" do
    request_record = create(
      :ai_request,
      note_revision: note.head_revision,
      status: "retrying",
      next_retry_at: 10.seconds.from_now
    )

    delete ai_request_dashboard_path(request_record)

    expect(response).to redirect_to(ai_requests_dashboard_path(status: "canceled", sort: "newest"))
    expect(request_record.reload.status).to eq("canceled")
    expect(request_record.next_retry_at).to be_nil
  end

  it "retries visible failed requests in batch" do
    failed_one = create(:ai_request, note_revision: note.head_revision, status: "failed", error_message: "a")
    failed_two = create(:ai_request, note_revision: note.head_revision, status: "failed", error_message: "b")
    succeeded = create(:ai_request, note_revision: note.head_revision, status: "succeeded")

    expect {
      post retry_visible_ai_requests_path, params: { status: "failed" }
    }.to have_enqueued_job(Ai::ReviewJob).exactly(2).times

    expect(response).to redirect_to(ai_requests_dashboard_path(sort: "newest"))
    expect(failed_one.reload.status).to eq("queued")
    expect(failed_two.reload.status).to eq("queued")
    expect(succeeded.reload.status).to eq("succeeded")
  end

  it "cancels visible active requests in batch" do
    retrying = create(:ai_request, note_revision: note.head_revision, status: "retrying", next_retry_at: 5.seconds.from_now)
    running = create(:ai_request, note_revision: note.head_revision, status: "running")
    failed = create(:ai_request, note_revision: note.head_revision, status: "failed")

    delete cancel_visible_ai_requests_path, params: { status: "retrying" }

    expect(response).to redirect_to(ai_requests_dashboard_path(status: "canceled", sort: "newest"))
    expect(retrying.reload.status).to eq("canceled")
    expect(running.reload.status).to eq("running")
    expect(failed.reload.status).to eq("failed")
  end
end
