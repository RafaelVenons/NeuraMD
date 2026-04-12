# frozen_string_literal: true

require "rails_helper"

RSpec.describe FileImports::ImportEnrichService do
  describe ".call" do
    let(:markdown) { "# Topico\n\nConteudo sobre redes neurais e backpropagation.\n" }

    context "when no provider is configured" do
      it "returns the original markdown unchanged" do
        allow(Ai::ProviderRegistry).to receive(:available_provider_names).and_return([])
        expect(described_class.call(markdown: markdown)).to eq(markdown)
      end
    end

    context "when the provider raises" do
      it "falls back to the original markdown" do
        allow(Ai::ProviderRegistry).to receive(:available_provider_names).and_return(["ollama"])
        provider = instance_double(Ai::OllamaProvider)
        allow(provider).to receive(:review).and_raise(Ai::RequestError, "boom")
        allow(Ai::ProviderRegistry).to receive(:resolve_selection).and_return(
          name: "ollama", model: "qwen3.5:2b", base_url: "http://x", api_key: nil
        )
        allow(Ai::OllamaProvider).to receive(:new).and_return(provider)

        expect(described_class.call(markdown: markdown)).to eq(markdown)
      end
    end

    context "when the model returns enriched markdown with slug links" do
      it "resolves slugs to UUIDs and returns enriched markdown" do
        note = create(:note, title: "Backpropagation")
        enriched = "# Topico\n\nConteudo sobre redes neurais e [[Backpropagation|f:#{note.slug}]].\n"

        allow(Ai::ProviderRegistry).to receive(:available_provider_names).and_return(["ollama"])
        allow(Ai::ProviderRegistry).to receive(:resolve_selection).and_return(
          name: "ollama", model: "qwen3.5:2b", base_url: "http://x", api_key: nil
        )
        provider = instance_double(Ai::OllamaProvider)
        allow(provider).to receive(:review).and_return(
          Ai::Result.new(content: enriched, provider: "ollama", model: "qwen3.5:2b", tokens_in: 0, tokens_out: 0)
        )
        allow(Ai::OllamaProvider).to receive(:new).and_return(provider)

        result = described_class.call(markdown: markdown)
        expect(result).to include("[[Backpropagation|f:#{note.id}]]")
      end

      it "rejects enriched output that changes more than 15% of the content" do
        create(:note, title: "Backpropagation")
        truncated = "# Topico\n\nConteudo curto.\n"

        allow(Ai::ProviderRegistry).to receive(:available_provider_names).and_return(["ollama"])
        allow(Ai::ProviderRegistry).to receive(:resolve_selection).and_return(
          name: "ollama", model: "qwen3.5:2b", base_url: "http://x", api_key: nil
        )
        provider = instance_double(Ai::OllamaProvider)
        allow(provider).to receive(:review).and_return(
          Ai::Result.new(content: truncated, provider: "ollama", model: "qwen3.5:2b", tokens_in: 0, tokens_out: 0)
        )
        allow(Ai::OllamaProvider).to receive(:new).and_return(provider)

        expect(described_class.call(markdown: markdown)).to eq(markdown)
      end
    end

    context "when the catalogue lookup yields no relevant notes" do
      it "skips the LLM call and returns the original markdown" do
        allow(Ai::ProviderRegistry).to receive(:available_provider_names).and_return(["ollama"])
        expect(Ai::OllamaProvider).not_to receive(:new)
        expect(described_class.call(markdown: markdown)).to eq(markdown)
      end
    end
  end
end
