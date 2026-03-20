require "rails_helper"

RSpec.describe "AI providers" do
  describe Ai::OpenaiCompatibleProvider do
    it "builds the prompt payload and parses string content responses" do
      provider = described_class.new(
        name: "openai",
        model: "gpt-4o-mini",
        base_url: "https://example.test/v1",
        api_key: "secret"
      )

      expect(provider).to receive(:post_json).with(
        "https://example.test/v1/chat/completions",
        headers: {"Authorization" => "Bearer secret"},
        body: hash_including(
          model: "gpt-4o-mini",
          messages: [
            hash_including(role: "system", content: include("Preferred language of the output: pt-BR.")),
            {role: "user", content: "Texto com erro."}
          ]
        )
      ).and_return(
        {
          "choices" => [{"message" => {"content" => "Texto corrigido."}}],
          "usage" => {"prompt_tokens" => 12, "completion_tokens" => 9}
        }
      )

      result = provider.review(capability: "grammar_review", text: "Texto com erro.", language: "pt-BR")

      expect(result.content).to eq("Texto corrigido.")
      expect(result.provider).to eq("openai")
      expect(result.model).to eq("gpt-4o-mini")
      expect(result.tokens_in).to eq(12)
      expect(result.tokens_out).to eq(9)
    end

    it "normalizes array-based content responses" do
      provider = described_class.new(
        name: "openai",
        model: "gpt-4o-mini",
        base_url: "https://example.test/v1",
        api_key: "secret"
      )

      allow(provider).to receive(:post_json).and_return(
        {
          "choices" => [{"message" => {"content" => [{"text" => "Texto "}, {"text" => "corrigido."}]}}],
          "usage" => {"prompt_tokens" => 8, "completion_tokens" => 5}
        }
      )

      result = provider.review(capability: "suggest", text: "Texto.", language: nil)

      expect(result.content).to eq("Texto corrigido.")
    end
  end

  describe Ai::AnthropicProvider do
    it "builds the prompt payload and parses content blocks" do
      provider = described_class.new(
        name: "anthropic",
        model: "claude-3-5-sonnet-latest",
        base_url: "https://example.test/v1",
        api_key: "secret"
      )

      expect(provider).to receive(:post_json).with(
        "https://example.test/v1/messages",
        headers: {
          "x-api-key" => "secret",
          "anthropic-version" => ENV.fetch("ANTHROPIC_VERSION", "2023-06-01")
        },
        body: hash_including(
          model: "claude-3-5-sonnet-latest",
          system: include("Preferred language of the output: pt-BR."),
          messages: [{role: "user", content: "Texto com erro."}]
        )
      ).and_return(
        {
          "content" => [{"text" => "Texto corrigido."}],
          "usage" => {"input_tokens" => 16, "output_tokens" => 11}
        }
      )

      result = provider.review(capability: "grammar_review", text: "Texto com erro.", language: "pt-BR")

      expect(result.content).to eq("Texto corrigido.")
      expect(result.provider).to eq("anthropic")
      expect(result.model).to eq("claude-3-5-sonnet-latest")
      expect(result.tokens_in).to eq(16)
      expect(result.tokens_out).to eq(11)
    end
  end

  describe Ai::OllamaProvider do
    it "builds the prompt payload and parses chat responses" do
      provider = described_class.new(
        name: "ollama",
        model: "qwen3.5:4b",
        base_url: "http://AIrch:11434",
        api_key: nil
      )

      expect(provider).to receive(:post_json).with(
        "http://AIrch:11434/api/chat",
        headers: {},
        body: hash_including(
          model: "qwen3.5:4b",
          stream: false,
          messages: [
            hash_including(role: "system", content: include("Preferred language of the output: pt-BR.")),
            {role: "user", content: "Texto com erro."}
          ]
        )
      ).and_return(
        {
          "message" => {"content" => "Texto corrigido."},
          "prompt_eval_count" => 21,
          "eval_count" => 14
        }
      )

      result = provider.review(capability: "grammar_review", text: "Texto com erro.", language: "pt-BR")

      expect(result.content).to eq("Texto corrigido.")
      expect(result.provider).to eq("ollama")
      expect(result.model).to eq("qwen3.5:4b")
      expect(result.tokens_in).to eq(21)
      expect(result.tokens_out).to eq(14)
    end
  end
end
