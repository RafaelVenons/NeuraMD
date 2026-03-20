require "rails_helper"

RSpec.describe Ai::ProviderRegistry do
  describe ".status" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:fetch).and_call_original
      %w[
        AI_ENABLED
        AI_PROVIDER
        AI_PROVIDER_PRIORITY
        AI_ENABLED_PROVIDERS
        OPENAI_API_KEY
        ANTHROPIC_API_KEY
        OLLAMA_API_KEY
        AZURE_OPENAI_API_KEY
        LOCAL_AI_API_KEY
        OPENAI_MODEL
        ANTHROPIC_MODEL
        OLLAMA_MODEL
        AZURE_OPENAI_MODEL
        LOCAL_AI_MODEL
        OPENAI_BASE_URL
        ANTHROPIC_BASE_URL
        OLLAMA_API_BASE
        AZURE_OPENAI_BASE_URL
        LOCAL_AI_BASE_URL
      ].each do |key|
        allow(ENV).to receive(:[]).with(key).and_return(nil)
      end
    end

    it "prefers the provider forced by ENV when available" do
      create(:ai_provider, name: "openai", enabled: true, default_model_text: "gpt-4o-mini")
      create(:ai_provider, name: "anthropic", enabled: true, default_model_text: "claude-3-5-sonnet-latest", config: {"models" => ["claude-3-5-sonnet-latest", "claude-3-7-sonnet-latest"]})

      allow(ENV).to receive(:[]).with("AI_PROVIDER").and_return("anthropic")
      allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return("secret")
      allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("secret")

      status = described_class.status

      expect(status[:enabled]).to be(true)
      expect(status[:provider]).to eq("anthropic")
      expect(status[:available_providers]).to include("openai", "anthropic")
      expect(status[:provider_options]).to include(
        include(
          name: "anthropic",
          default_model: "claude-3-5-sonnet-latest",
          models: include("claude-3-5-sonnet-latest", "claude-3-7-sonnet-latest")
        )
      )
    end

    it "disables AI when no provider is configured" do
      status = described_class.status

      expect(status[:enabled]).to be(false)
      expect(status[:provider]).to be_nil
      expect(status[:available_providers]).to eq([])
    end
  end

  describe ".build" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("AI_ENABLED_PROVIDERS").and_return("openai")
      allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("secret")
      allow(ENV).to receive(:[]).with("OPENAI_MODEL").and_return("gpt-4o-mini")
      allow(ENV).to receive(:[]).with("OPENAI_BASE_URL").and_return("https://example.test/v1")
    end

    it "accepts an explicit model override" do
      provider = described_class.build("openai", model_name: "gpt-4.1-mini")

      expect(provider.name).to eq("openai")
      expect(provider.model).to eq("gpt-4.1-mini")
    end
  end
end
