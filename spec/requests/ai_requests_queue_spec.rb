require "rails_helper"

RSpec.describe "AI requests queue API", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it "returns the global queue as json" do
    note = create(:note, :with_head_revision)
    other_note = create(:note, :with_head_revision, title: "Nota Global")
    translated_note = create(:note, :with_head_revision, title: "Nota Global Traduzida", detected_language: "en-US")
    request_record = create(
      :ai_request,
      note_revision: note.head_revision,
      capability: "grammar_review",
      provider: "openai",
      requested_provider: "openai",
      model: "gpt-4o-mini",
      status: "queued"
    )
    completed_request = create(
      :ai_request,
      note_revision: other_note.head_revision,
      capability: "translate",
      provider: "openai",
      requested_provider: "openai",
      model: "gpt-4o-mini",
      status: "succeeded",
      completed_at: Time.current,
      metadata: {
        "translated_note_id" => translated_note.id
      }
    )

    get ai_requests_dashboard_path(format: :json)

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["requests"]).to include(
      a_hash_including(
        "id" => request_record.id,
        "note_slug" => note.slug,
        "note_title" => note.title,
        "status" => "queued"
      )
    )
    expect(body["recent_history"]).to include(
      a_hash_including(
        "id" => completed_request.id,
        "note_slug" => other_note.slug,
        "note_title" => "Nota Global",
        "translated_note_slug" => translated_note.slug,
        "status" => "succeeded",
        "result_applicable" => false,
        "translation_applied_at" => nil
      )
    )
  end

  it "exposes applicability metadata for succeeded requests" do
    note = create(:note, :with_head_revision)
    applicable_request = create(
      :ai_request,
      note_revision: note.head_revision,
      capability: "rewrite",
      provider: "openai",
      requested_provider: "openai",
      model: "gpt-4o-mini",
      status: "succeeded",
      output_text: "Texto revisado",
      completed_at: Time.current
    )
    accepted_request = create(
      :ai_request,
      note_revision: note.head_revision,
      capability: "grammar_review",
      provider: "openai",
      requested_provider: "openai",
      model: "gpt-4o-mini",
      status: "succeeded",
      output_text: "Texto aceito",
      completed_at: Time.current,
      metadata: {
        "language" => "pt-BR",
        "accepted_at" => Time.current.iso8601
      }
    )

    get ai_requests_dashboard_path(format: :json)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["recent_history"]).to include(
      a_hash_including(
        "id" => applicable_request.id,
        "result_applicable" => true,
        "accepted_at" => nil
      ),
      a_hash_including(
        "id" => accepted_request.id,
        "result_applicable" => false
      )
    )
  end

  it "reorders active requests globally" do
    note_one = create(:note, :with_head_revision)
    note_two = create(:note, :with_head_revision)
    first = create(:ai_request, note_revision: note_one.head_revision, status: "queued", queue_position: 1)
    second = create(:ai_request, note_revision: note_two.head_revision, status: "retrying", queue_position: 2)

    patch reorder_ai_requests_dashboard_path,
      params: {ordered_request_ids: [second.id, first.id]},
      as: :json

    expect(response).to have_http_status(:ok)
    expect(first.reload.queue_position).to eq(2)
    expect(second.reload.queue_position).to eq(1)
  end

  it "undoes a succeeded seed_note request globally" do
    source_note = create(:note, :with_head_revision)
    promise_note = create(:note, title: "Promessa Global")
    Notes::DraftService.call(note: source_note, content: "Abrir [[Promessa Global|#{promise_note.id}]]", author: user)
    request_record = create(
      :ai_request,
      note_revision: source_note.head_revision,
      capability: "seed_note",
      status: "succeeded",
      metadata: {
        "language" => source_note.detected_language,
        "promise_source_note_id" => source_note.id,
        "promise_note_id" => promise_note.id,
        "promise_note_title" => promise_note.title
      }
    )

    delete ai_request_dashboard_path(request_record.id), as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include(
      "id" => request_record.id,
      "status" => "succeeded",
      "undone" => true,
      "promise_note_id" => promise_note.id,
      "promise_note_deleted" => true,
      "restored_content" => "Abrir [[Promessa Global]]",
      "graph_changed" => true
    )
    expect(promise_note.reload).to be_deleted
  end

  it "does not expose queue navigation for a deleted promise note" do
    note = create(:note, :with_head_revision)
    deleted_promise = create(:note, title: "Gigante")
    deleted_promise.soft_delete!
    request_record = create(
      :ai_request,
      note_revision: note.head_revision,
      capability: "seed_note",
      status: "succeeded",
      metadata: {
        "language" => note.detected_language,
        "promise_note_id" => deleted_promise.id,
        "promise_note_title" => deleted_promise.title
      }
    )

    get ai_requests_dashboard_path(format: :json)

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body["requests"].find { |item| item["id"] == request_record.id }
    expect(payload).to include(
      "promise_note_id" => deleted_promise.id,
      "promise_note_title" => "Gigante",
      "promise_note_slug" => nil
    )
  end

  it "hides a resolved queue request from future queue loads" do
    note = create(:note, :with_head_revision)
    request_record = create(
      :ai_request,
      note_revision: note.head_revision,
      capability: "grammar_review",
      provider: "openai",
      requested_provider: "openai",
      model: "gpt-4o-mini",
      status: "succeeded",
      completed_at: Time.current
    )

    patch resolve_ai_request_queue_path(request_record.id), as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include(
      "id" => request_record.id,
      "queue_hidden" => true
    )

    get ai_requests_dashboard_path(format: :json)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["requests"]).not_to include(a_hash_including("id" => request_record.id))
    expect(response.parsed_body["recent_history"]).to include(a_hash_including("id" => request_record.id))
  end

  it "applies a succeeded seed_note request only when the queue item is resolved" do
    source_note = create(:note, :with_head_revision)
    promise_note = create(:note, title: "Promessa Aplicada", head_revision: nil)
    request_record = create(
      :ai_request,
      note_revision: source_note.head_revision,
      capability: "seed_note",
      status: "succeeded",
      provider: "ollama",
      requested_provider: "ollama",
      model: "qwen2.5:1.5b",
      output_text: "# Promessa Aplicada\n\nConteudo vindo da IA.",
      metadata: {
        "language" => source_note.detected_language,
        "requested_by_id" => user.id,
        "promise_note_id" => promise_note.id,
        "promise_note_title" => promise_note.title
      }
    )

    expect(promise_note.reload.head_revision).to be_nil

    patch resolve_ai_request_queue_path(request_record.id), as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include(
      "id" => request_record.id,
      "queue_hidden" => true
    )

    promise_note.reload
    expect(promise_note.head_revision).to be_present
    expect(promise_note.head_revision.content_markdown).to eq("# Promessa Aplicada\n\nConteudo vindo da IA.")
    expect(request_record.reload.metadata["promise_checkpoint_revision_id"]).to eq(promise_note.head_revision.id)
  end

  it "keeps an undone seed_note request hidden from future queue loads" do
    source_note = create(:note, :with_head_revision)
    promise_note = create(:note, title: "Promessa Persistida")
    Notes::DraftService.call(note: source_note, content: "Abrir [[Promessa Persistida|#{promise_note.id}]]", author: user)
    request_record = create(
      :ai_request,
      note_revision: source_note.head_revision,
      capability: "seed_note",
      status: "succeeded",
      metadata: {
        "language" => source_note.detected_language,
        "promise_source_note_id" => source_note.id,
        "promise_note_id" => promise_note.id,
        "promise_note_title" => promise_note.title
      }
    )

    delete ai_request_dashboard_path(request_record.id), as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include(
      "id" => request_record.id,
      "undone" => true,
      "queue_hidden" => true
    )

    get ai_requests_dashboard_path(format: :json)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["requests"]).not_to include(a_hash_including("id" => request_record.id))
    expect(response.parsed_body["recent_history"]).to include(a_hash_including("id" => request_record.id))
  end
end
