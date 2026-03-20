require "rails_helper"

RSpec.describe "AI", type: :request do
  let(:user) { create(:user) }
  let(:note) { create(:note, :with_head_revision) }

  before { sign_in user }

  describe "GET /notes/:slug/ai_status" do
    it "returns provider status for the editor" do
      allow(Ai::ReviewService).to receive(:status).and_return(
        {
          enabled: true,
          provider: "openai",
          model: "gpt-4o-mini",
          available_providers: ["openai"],
          provider_options: [
            {
              name: "openai",
              label: "OpenAI",
              default_model: "gpt-4o-mini",
              models: ["gpt-4o-mini", "gpt-4.1-mini"],
              selected: true,
              selected_model: "gpt-4o-mini"
            }
          ]
        }
      )

      get ai_status_note_path(note.slug)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        "enabled" => true,
        "provider" => "openai",
        "model" => "gpt-4o-mini"
      )
      expect(response.parsed_body["provider_options"]).to include(
        include(
          "name" => "openai",
          "models" => include("gpt-4o-mini", "gpt-4.1-mini")
        )
      )
    end
  end

  describe "GET /notes/:slug" do
    it "renders the note editor subscribed to the note AI stream" do
      get note_path(note.slug)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("turbo-cable-stream-source")
      expect(response.body).to include("editor-root")
    end
  end

  describe "POST /notes/:slug/ai_review" do
    let(:headers) { {"Content-Type" => "application/json", "Accept" => "application/json"} }
    let(:document_markdown) { note.head_revision.content_markdown }
    let(:provider) { instance_double(Ai::OpenaiCompatibleProvider, name: "openai", model: "gpt-4o-mini") }

    it "enqueues grammar review and persists the queued request" do
      allow(Ai::ProviderRegistry).to receive(:build).and_return(provider)

      expect {
        post ai_review_note_path(note.slug),
          params: {
            capability: "grammar_review",
            text: "Texto com erro.",
            document_markdown: document_markdown
          }.to_json,
          headers: headers
      }.to change(AiRequest, :count).by(1)
        .and have_enqueued_job(Ai::ReviewJob)

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["status"]).to eq("queued")

      request = AiRequest.recent_first.first
      expect(request.note_revision).to eq(note.head_revision)
      expect(request.capability).to eq("grammar_review")
      expect(request.status).to eq("queued")
      expect(request.model).to eq("gpt-4o-mini")
      expect(request.input_text).to eq("Texto com erro.")
      expect(request.prompt_summary).to include("grammar_review")
    end

    it "passes explicit provider and model selection to the review service" do
      expect(Ai::ReviewService).to receive(:enqueue).with(
        note: note,
        note_revision: note.head_revision,
        capability: "grammar_review",
        text: "Texto com erro.",
        language: note.detected_language,
        provider_name: "openai",
        model_name: "gpt-4.1-mini",
        requested_by: user
      ).and_return(create(:ai_request, note_revision: note.head_revision, provider: "openai", requested_provider: "openai", model: "gpt-4.1-mini"))

      post ai_review_note_path(note.slug),
        params: {
          capability: "grammar_review",
          provider: "openai",
          model: "gpt-4.1-mini",
          text: "Texto com erro.",
          document_markdown: document_markdown
        }.to_json,
        headers: headers

      expect(response).to have_http_status(:accepted)
    end

    it "rejects empty text" do
      post ai_review_note_path(note.slug),
        params: {
          capability: "grammar_review",
          text: "",
          document_markdown: document_markdown
        }.to_json,
        headers: headers

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq("Nenhum texto para processar.")
    end
  end

  describe "GET /notes/:slug/ai_requests/:request_id" do
    it "returns the persisted status for a completed request" do
      request_record = create(
        :ai_request,
        note_revision: note.head_revision,
        status: "succeeded",
        provider: "openai",
        model: "gpt-4o-mini",
        output_text: "Texto corrigido.",
        started_at: 3.seconds.ago,
        completed_at: 1.second.ago
      )

      get ai_request_note_path(note.slug, request_record.id)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        "id" => request_record.id,
        "status" => "succeeded",
        "provider" => "openai",
        "model" => "gpt-4o-mini",
        "capability" => "grammar_review",
        "attempts_count" => 0,
        "max_attempts" => 3,
        "corrected" => "Texto corrigido."
      )
      expect(response.parsed_body["duration_ms"]).to be >= 1000
      expect(response.parsed_body["duration_human"]).to be_present
      expect(response.parsed_body["created_at"]).to be_present
    end
  end

  describe "GET /notes/:slug/ai_requests" do
    it "returns recent requests ordered by creation time" do
      older = create(:ai_request, note_revision: note.head_revision, status: "failed", created_at: 2.hours.ago)
      newer = create(:ai_request, note_revision: note.head_revision, status: "succeeded", created_at: 1.hour.ago)

      get ai_requests_note_path(note.slug), params: { limit: 5 }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["requests"].map { |item| item["id"] }).to eq([newer.id, older.id])
      expect(response.parsed_body["requests"].first).to include(
        "status" => "succeeded",
        "capability" => "grammar_review"
      )
    end
  end

  describe "DELETE /notes/:slug/ai_requests/:request_id" do
    it "cancels an active request" do
      request_record = create(
        :ai_request,
        note_revision: note.head_revision,
        status: "retrying",
        next_retry_at: 5.seconds.from_now
      )

      delete ai_request_note_path(note.slug, request_record.id), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        "id" => request_record.id,
        "status" => "canceled"
      )

      expect(request_record.reload.status).to eq("canceled")
      expect(request_record.next_retry_at).to be_nil
      expect(request_record.completed_at).to be_present
    end
  end
end
