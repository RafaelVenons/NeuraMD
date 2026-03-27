require "rails_helper"

RSpec.describe Tts::BaseProvider do
  let(:provider) { described_class.new(name: "test_tts", base_url: "http://tts.example.com") }

  describe "#initialize" do
    it "stores name and base_url" do
      expect(provider.name).to eq("test_tts")
      expect(provider.base_url).to eq("http://tts.example.com")
    end

    it "accepts optional api_key" do
      p = described_class.new(name: "cloud", base_url: "https://api.example.com", api_key: "sk-123")
      expect(p.api_key).to eq("sk-123")
    end
  end

  describe "#synthesize" do
    it "raises NotImplementedError" do
      expect { provider.synthesize(text: "hello", voice: "v1", language: "en", model: nil, format: "mp3", settings: {}) }
        .to raise_error(NotImplementedError)
    end
  end

  describe "#post_binary (private)" do
    let(:url) { "http://tts.example.com/v1/tts" }
    let(:headers) { {"Authorization" => "Bearer key"} }
    let(:body) { {text: "hello"} }

    def stub_http(status:, response_body:, response_class: nil)
      response = instance_double(Net::HTTPResponse, body: response_body, code: status.to_s)
      allow(response).to receive(:is_a?).and_return(false)

      case status
      when 200..299
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      when 429
        allow(response).to receive(:is_a?).with(Net::HTTPTooManyRequests).and_return(true)
      when 500..599
        allow(response).to receive(:is_a?).with(Net::HTTPServerError).and_return(true)
      end

      http = instance_double(Net::HTTP)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:write_timeout=)
      allow(http).to receive(:request).and_return(response)
      allow(Net::HTTP).to receive(:new).and_return(http)
      http
    end

    it "returns raw binary response on success" do
      audio_bytes = "\xFF\xFB\x90\x00".b
      stub_http(status: 200, response_body: audio_bytes)

      result = provider.send(:post_binary, url, headers: headers, body: body)
      expect(result).to eq(audio_bytes)
      expect(result.encoding).to eq(Encoding::ASCII_8BIT)
    end

    it "raises RequestError on 400" do
      stub_http(status: 400, response_body: '{"error":"bad request"}')

      expect { provider.send(:post_binary, url, headers: headers, body: body) }
        .to raise_error(Tts::RequestError, /bad request/)
    end

    it "raises TransientRequestError on 429" do
      stub_http(status: 429, response_body: '{"error":"rate limited"}')

      expect { provider.send(:post_binary, url, headers: headers, body: body) }
        .to raise_error(Tts::TransientRequestError)
    end

    it "raises TransientRequestError on 500" do
      stub_http(status: 500, response_body: '{"error":"server error"}')

      expect { provider.send(:post_binary, url, headers: headers, body: body) }
        .to raise_error(Tts::TransientRequestError)
    end

    it "raises TransientRequestError on connection refused" do
      allow(Net::HTTP).to receive(:new).and_raise(Errno::ECONNREFUSED)

      expect { provider.send(:post_binary, url, headers: headers, body: body) }
        .to raise_error(Tts::TransientRequestError, /indisponivel/)
    end

    it "raises RequestError with fallback message on non-JSON error body" do
      stub_http(status: 400, response_body: "plain text error")

      expect { provider.send(:post_binary, url, headers: headers, body: body) }
        .to raise_error(Tts::RequestError, /Falha na chamada ao provider test_tts/)
    end
  end
end
