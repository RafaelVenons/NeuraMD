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
          available_providers: ["openai"]
        }
      )

      get ai_status_note_path(note.slug)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        "enabled" => true,
        "provider" => "openai",
        "model" => "gpt-4o-mini"
      )
    end
  end

  describe "POST /notes/:slug/ai_review" do
    let(:headers) { {"Content-Type" => "application/json", "Accept" => "application/json"} }
    let(:document_markdown) { note.head_revision.content_markdown }
    let(:provider) do
      instance_double(
        Ai::OpenaiCompatibleProvider,
        review: Ai::Result.new(
          content: "Texto corrigido.",
          provider: "openai",
          model: "gpt-4o-mini",
          tokens_in: 12,
          tokens_out: 9
        )
      )
    end

    before do
      allow(Ai::ProviderRegistry).to receive(:build).and_return(provider)
    end

    it "processes grammar review and audits the request" do
      expect {
        post ai_review_note_path(note.slug),
          params: {
            capability: "grammar_review",
            text: "Texto com erro.",
            document_markdown: document_markdown
          }.to_json,
          headers: headers
      }.to change(AiRequest, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        "original" => "Texto com erro.",
        "corrected" => "Texto corrigido.",
        "provider" => "openai",
        "model" => "gpt-4o-mini"
      )

      audit = AiRequest.order(:created_at).last
      expect(audit.note_revision).to eq(note.head_revision)
      expect(audit.capability).to eq("grammar_review")
      expect(audit.provider).to eq("openai")
      expect(audit.tokens_in).to eq(12)
      expect(audit.tokens_out).to eq(9)
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
end
