# frozen_string_literal: true

require "rails_helper"

RSpec.describe FileImports::AiAnalyzeService do
  let(:markdown) do
    <<~MD
      # Document Title

      ## Chapter 1: Introduction

      This is the introduction paragraph with enough content.
      It covers the basics of the topic at hand.
      Multiple lines of content here to make it substantial.
      More content follows in this section for completeness.

      ## Chapter 2: Methods

      This section describes the methodology used.
      Several approaches were considered and evaluated.
      The final method was chosen based on empirical results.
      Additional details about the implementation follow.

      ## Chapter 3: Results

      The results show significant improvements.
      Data analysis revealed interesting patterns.
      Further investigation confirmed the findings.
      Conclusions were drawn from the data collected.
    MD
  end

  let(:lines) { markdown.lines.map(&:chomp) }

  describe ".call" do
    context "when AI returns valid suggestions" do
      let(:ai_response) do
        [
          {"title" => "Introduction", "start_line" => 0, "end_line" => 8, "reason" => "First chapter"},
          {"title" => "Methods", "start_line" => 9, "end_line" => 16, "reason" => "Second chapter"},
          {"title" => "Results", "start_line" => 17, "end_line" => lines.size - 1, "reason" => "Third chapter"}
        ].to_json
      end

      before do
        provider = instance_double(Ai::OllamaProvider)
        allow(provider).to receive(:review).and_return(
          Ai::Result.new(content: ai_response, provider: "ollama", model: "test", tokens_in: 100, tokens_out: 50)
        )
        allow(Ai::ProviderRegistry).to receive(:available_provider_names).and_return(["ollama"])
        allow(Ai::ProviderRegistry).to receive(:enabled?).and_return(true)
        allow(Ai::ProviderRegistry).to receive(:resolve_selection).and_return(
          {name: "ollama", model: "test", base_url: "http://test:11434", api_key: nil}
        )
        allow(Ai::OllamaProvider).to receive(:new).and_return(provider)
      end

      it "returns array of Suggestion structs" do
        result = described_class.call(markdown: markdown)
        expect(result).to be_an(Array)
        expect(result.size).to eq(3)
        expect(result.first).to be_a(FileImports::SplitSuggestionService::Suggestion)
        expect(result.first.title).to eq("Introduction")
      end

      it "ensures contiguous coverage from 0 to last line" do
        result = described_class.call(markdown: markdown)
        expect(result.first.start_line).to eq(0)
        expect(result.last.end_line).to eq(lines.size - 1)
      end
    end

    context "when AI returns a single entry (no split)" do
      before do
        provider = instance_double(Ai::OllamaProvider)
        allow(provider).to receive(:review).and_return(
          Ai::Result.new(
            content: [{"title" => "Full Document", "start_line" => 0, "end_line" => lines.size - 1, "reason" => "No clear split points"}].to_json,
            provider: "ollama", model: "test", tokens_in: 100, tokens_out: 50
          )
        )
        allow(Ai::ProviderRegistry).to receive(:available_provider_names).and_return(["ollama"])
        allow(Ai::ProviderRegistry).to receive(:enabled?).and_return(true)
        allow(Ai::ProviderRegistry).to receive(:resolve_selection).and_return(
          {name: "ollama", model: "test", base_url: "http://test:11434", api_key: nil}
        )
        allow(Ai::OllamaProvider).to receive(:new).and_return(provider)
      end

      it "returns single suggestion" do
        result = described_class.call(markdown: markdown)
        expect(result.size).to eq(1)
        expect(result.first.title).to eq("Full Document")
      end
    end

    context "when AI is unavailable" do
      before do
        allow(Ai::ProviderRegistry).to receive(:available_provider_names).and_return([])
        allow(Ai::ProviderRegistry).to receive(:enabled?).and_return(false)
      end

      it "returns nil" do
        result = described_class.call(markdown: markdown)
        expect(result).to be_nil
      end
    end

    context "when AI returns invalid JSON" do
      before do
        provider = instance_double(Ai::OllamaProvider)
        allow(provider).to receive(:review).and_return(
          Ai::Result.new(content: "This is not JSON", provider: "ollama", model: "test", tokens_in: 100, tokens_out: 50)
        )
        allow(Ai::ProviderRegistry).to receive(:available_provider_names).and_return(["ollama"])
        allow(Ai::ProviderRegistry).to receive(:enabled?).and_return(true)
        allow(Ai::ProviderRegistry).to receive(:resolve_selection).and_return(
          {name: "ollama", model: "test", base_url: "http://test:11434", api_key: nil}
        )
        allow(Ai::OllamaProvider).to receive(:new).and_return(provider)
      end

      it "returns nil (fallback)" do
        result = described_class.call(markdown: markdown)
        expect(result).to be_nil
      end
    end

    context "when AI raises an error" do
      before do
        provider = instance_double(Ai::OllamaProvider)
        allow(provider).to receive(:review).and_raise(Ai::TransientRequestError, "timeout")
        allow(Ai::ProviderRegistry).to receive(:available_provider_names).and_return(["ollama"])
        allow(Ai::ProviderRegistry).to receive(:enabled?).and_return(true)
        allow(Ai::ProviderRegistry).to receive(:resolve_selection).and_return(
          {name: "ollama", model: "test", base_url: "http://test:11434", api_key: nil}
        )
        allow(Ai::OllamaProvider).to receive(:new).and_return(provider)
      end

      it "returns nil (graceful fallback)" do
        result = described_class.call(markdown: markdown)
        expect(result).to be_nil
      end
    end

    it "returns nil for empty markdown" do
      result = described_class.call(markdown: "")
      expect(result).to be_nil
    end
  end
end
