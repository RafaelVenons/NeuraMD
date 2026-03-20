require "rails_helper"

RSpec.describe Ai::ReviewService do
  let(:note) { create(:note, :with_head_revision) }
  let(:note_revision) { note.head_revision }

  describe ".enqueue" do
    it "creates a queued ai_request and enqueues the job" do
      provider = instance_double(Ai::OpenaiCompatibleProvider, name: "openai", model: "gpt-4o-mini")
      allow(Ai::ProviderRegistry).to receive(:resolve_selection).and_return(
        {
          name: "openai",
          model: "gpt-4o-mini",
          selection_strategy: "configured_default",
          selection_reason: "provider_non_ollama"
        }
      )
      allow(Ai::ProviderRegistry).to receive(:build).and_return(provider)

      expect {
        described_class.enqueue(
          note: note,
          note_revision: note_revision,
          capability: "grammar_review",
          text: "Texto com erro.",
          language: "pt-BR"
        )
      }.to change(AiRequest, :count).by(1)
        .and have_enqueued_job(Ai::ReviewJob)
        .on_queue("ai_remote")

      request = AiRequest.recent_first.first
      expect(request.status).to eq("queued")
      expect(request.provider).to eq("openai")
      expect(request.requested_provider).to eq("openai")
      expect(request.model).to eq("gpt-4o-mini")
      expect(request.attempts_count).to eq(0)
      expect(request.max_attempts).to eq(3)
      expect(request.input_text).to eq("Texto com erro.")
    end

    it "persists the explicit provider/model requested by the UI" do
      provider = instance_double(Ai::OpenaiCompatibleProvider, name: "openai", model: "gpt-4.1-mini")
      allow(Ai::ProviderRegistry).to receive(:build).with("openai", model_name: "gpt-4.1-mini").and_return(provider)
      allow(Ai::ProviderRegistry).to receive(:resolve_selection).with(
        "openai",
        model_name: "gpt-4.1-mini",
        capability: "grammar_review",
        text: "Texto com erro.",
        language: "pt-BR",
        target_language: nil
      ).and_return(
        {
          name: "openai",
          model: "gpt-4.1-mini",
          selection_strategy: "manual_override",
          selection_reason: "ui_override"
        }
      )

      described_class.enqueue(
        note: note,
        note_revision: note_revision,
        capability: "grammar_review",
        text: "Texto com erro.",
        language: "pt-BR",
        provider_name: "openai",
        model_name: "gpt-4.1-mini"
      )

      request = AiRequest.recent_first.first
      expect(request.requested_provider).to eq("openai")
      expect(request.model).to eq("gpt-4.1-mini")
      expect(request.metadata["requested_model"]).to eq("gpt-4.1-mini")
      expect(request.metadata["model_selection_strategy"]).to eq("manual_override")
      expect(request.metadata["model_selection_reason"]).to eq("ui_override")
    end

    it "persists the automatic model selection metadata for ollama routing" do
      provider = instance_double(Ai::OllamaProvider, name: "ollama", model: "qwen2.5:0.5b")
      allow(Ai::ProviderRegistry).to receive(:resolve_selection).and_return(
        {
          name: "ollama",
          model: "qwen2.5:0.5b",
          selection_strategy: "automatic",
          selection_reason: "grammar_short"
        }
      )
      allow(Ai::ProviderRegistry).to receive(:build).with("ollama", model_name: "qwen2.5:0.5b").and_return(provider)

      described_class.enqueue(
        note: note,
        note_revision: note_revision,
        capability: "grammar_review",
        text: "Texto curto com erro.",
        language: "pt-BR"
      )

      request = AiRequest.recent_first.first
      expect(request.model).to eq("qwen2.5:0.5b")
      expect(request.metadata["model_selection_strategy"]).to eq("automatic")
      expect(request.metadata["model_selection_reason"]).to eq("grammar_short")
    end
  end

  describe ".process_request!" do
    it "persists a successful provider response" do
      request = create(:ai_request, note_revision: note_revision, provider: "openai", input_text: "Texto com erro.")
      provider = instance_double(
        Ai::OpenaiCompatibleProvider,
        review: Ai::Result.new(
          content: "Texto corrigido.",
          provider: "openai",
          model: "gpt-4o-mini",
          tokens_in: 12,
          tokens_out: 9
        )
      )

      allow(Ai::ProviderRegistry).to receive(:build).and_return(provider)

      outcome = described_class.process_request!(request)
      request.reload

      expect(outcome).to eq(:succeeded)
      expect(request.status).to eq("succeeded")
      expect(request.attempts_count).to eq(1)
      expect(request.output_text).to eq("Texto corrigido.")
      expect(request.model).to eq("gpt-4o-mini")
      expect(request.tokens_in).to eq(12)
      expect(request.tokens_out).to eq(9)
      expect(request.completed_at).to be_present
    end

    it "schedules retry for transient failures" do
      request = create(:ai_request, note_revision: note_revision, provider: "openai", input_text: "Texto com erro.")

      allow(Ai::ProviderRegistry).to receive(:build).and_raise(Ai::TransientRequestError, "openai indisponivel")

      freeze_time do
        outcome = described_class.process_request!(request)
        request.reload

        expect(outcome).to include(status: :retrying)
        expect(request.status).to eq("retrying")
        expect(request.attempts_count).to eq(1)
        expect(request.last_error_kind).to eq("transient")
        expect(request.next_retry_at).to eq(2.seconds.from_now)
        expect(request.completed_at).to be_nil
      end
    end

    it "marks the request as failed when retries are exhausted" do
      request = create(
        :ai_request,
        note_revision: note_revision,
        provider: "openai",
        input_text: "Texto com erro.",
        attempts_count: 2,
        max_attempts: 3
      )

      allow(Ai::ProviderRegistry).to receive(:build).and_raise(Ai::TransientRequestError, "openai indisponivel")

      outcome = described_class.process_request!(request)
      request.reload

      expect(outcome).to include(status: :failed)
      expect(request.status).to eq("failed")
      expect(request.attempts_count).to eq(3)
      expect(request.last_error_kind).to eq("transient")
      expect(request.completed_at).to be_present
      expect(request.next_retry_at).to be_nil
    end

    it "persists a permanent failed provider response" do
      request = create(:ai_request, note_revision: note_revision, provider: "openai", input_text: "Texto com erro.")

      allow(Ai::ProviderRegistry).to receive(:build).and_raise(Ai::ProviderUnavailableError, "IA nao configurada.")

      outcome = described_class.process_request!(request)

      request.reload
      expect(outcome).to include(status: :failed)
      expect(request.status).to eq("failed")
      expect(request.last_error_kind).to eq("permanent")
      expect(request.error_message).to eq("IA nao configurada.")
      expect(request.completed_at).to be_present
    end
  end

  describe ".cancel_request!" do
    it "marks an active request as canceled" do
      request = create(:ai_request, note_revision: note_revision, status: "retrying", next_retry_at: 5.seconds.from_now)

      described_class.cancel_request!(request)
      request.reload

      expect(request.status).to eq("canceled")
      expect(request.next_retry_at).to be_nil
      expect(request.completed_at).to be_present
    end

    it "keeps terminal requests unchanged" do
      request = create(:ai_request, note_revision: note_revision, status: "succeeded", completed_at: Time.current)

      described_class.cancel_request!(request)
      expect(request.reload.status).to eq("succeeded")
    end
  end
end
