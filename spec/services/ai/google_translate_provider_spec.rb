require "rails_helper"

RSpec.describe Ai::GoogleTranslateProvider do
  let(:provider) do
    described_class.new(
      name: "google_translate",
      model: "free",
      base_url: "https://translate.googleapis.com"
    )
  end

  describe "#review" do
    it "rejects non-translate capabilities" do
      expect {
        provider.review(capability: "grammar_review", text: "Olá", language: "pt-BR", target_language: "en")
      }.to raise_error(Ai::RequestError, /somente tradução/i)
    end

    it "rejects blank text" do
      expect {
        provider.review(capability: "translate", text: "", language: "pt-BR", target_language: "en")
      }.to raise_error(Ai::RequestError, /Texto vazio/i)
    end

    it "rejects missing target language" do
      expect {
        provider.review(capability: "translate", text: "Olá", language: "pt-BR", target_language: nil)
      }.to raise_error(Ai::RequestError, /Idioma alvo/i)
    end

    it "translates text and returns Result struct" do
      expect(provider).to receive(:fetch_translation)
        .with("Olá mundo", "pt", "en")
        .and_return("Hello world")

      result = provider.review(
        capability: "translate",
        text: "Olá mundo",
        language: "pt-BR",
        target_language: "en-US"
      )

      expect(result).to be_a(Ai::Result)
      expect(result.content).to eq("Hello world")
      expect(result.provider).to eq("google_translate")
      expect(result.model).to eq("free")
      expect(result.tokens_in).to be_nil
      expect(result.tokens_out).to be_nil
    end

    it "normalizes language codes (pt-BR → pt, en-US → en)" do
      expect(provider).to receive(:fetch_translation)
        .with("Olá", "pt", "en")
        .and_return("Hello")

      provider.review(capability: "translate", text: "Olá", language: "pt-BR", target_language: "en-US")
    end

    it "uses auto-detect when source language is nil" do
      expect(provider).to receive(:fetch_translation)
        .with("Hello", "auto", "pt")
        .and_return("Olá")

      provider.review(capability: "translate", text: "Hello", language: nil, target_language: "pt-BR")
    end

    it "preserves wikilinks by extracting them before translation" do
      expect(provider).to receive(:fetch_translation)
        .with("Eu gosto de \u0000WL0\u0000 e \u0000WL1\u0000", "pt", "en")
        .and_return("I like \u0000WL0\u0000 and \u0000WL1\u0000")

      result = provider.review(
        capability: "translate",
        text: "Eu gosto de [[Gatos|abc-123]] e [[Cães|def-456]]",
        language: "pt-BR",
        target_language: "en-US"
      )

      expect(result.content).to include("[[Gatos|abc-123]]")
      expect(result.content).to include("[[Cães|def-456]]")
    end

    it "raises RequestError when translation is empty" do
      expect(provider).to receive(:fetch_translation)
        .and_return("")

      expect {
        provider.review(capability: "translate", text: "Olá", language: "pt-BR", target_language: "en")
      }.to raise_error(Ai::RequestError, /vazio/i)
    end
  end

  describe "#fetch_translation (integration)" do
    it "builds correct URL and parses Google Translate response" do
      response_body = [[["Hello world", "Olá mundo", nil, nil, 10]]]

      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:request).and_return(
        instance_double(Net::HTTPSuccess, body: JSON.generate(response_body), is_a?: true, code: "200").tap do |resp|
          allow(resp).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        end
      )

      result = provider.send(:fetch_translation, "Olá mundo", "pt", "en")
      expect(result).to eq("Hello world")
    end

    it "joins multi-sentence translations" do
      response_body = [[["Hello. ", "Olá. ", nil, nil, 10], ["How are you?", "Como vai?", nil, nil, 10]]]

      http_double = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:request).and_return(
        instance_double(Net::HTTPSuccess, body: JSON.generate(response_body)).tap do |resp|
          allow(resp).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        end
      )

      result = provider.send(:fetch_translation, "Olá. Como vai?", "pt", "en")
      expect(result).to eq("Hello. How are you?")
    end
  end
end
