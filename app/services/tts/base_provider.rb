require "json"
require "net/http"
require "uri"
require_relative "error"
require_relative "result"

module Tts
  class BaseProvider
    attr_reader :name, :base_url, :api_key

    def initialize(name:, base_url:, api_key: nil)
      @name = name
      @base_url = base_url
      @api_key = api_key
    end

    def synthesize(text:, voice:, language:, model:, format:, settings:)
      raise NotImplementedError, "#{self.class}#synthesize must be implemented"
    end

    private

    def post_binary(url, headers:, body:)
      uri = URI.parse(url)
      request = Net::HTTP::Post.new(uri)
      headers.each { |key, value| request[key] = value }
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(body)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = tts_open_timeout
      http.read_timeout = tts_read_timeout
      http.write_timeout = tts_write_timeout if http.respond_to?(:write_timeout=)
      response = http.request(request)

      if response.is_a?(Net::HTTPSuccess)
        response.body.force_encoding(Encoding::ASCII_8BIT)
      else
        message = extract_error_message(response.body) || "Falha na chamada ao provider #{name}."
        error_class = retryable_response?(response) ? TransientRequestError : RequestError
        raise error_class, message
      end
    rescue SocketError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
      raise TransientRequestError, "#{name} indisponivel: #{e.message}"
    end

    def extract_error_message(body)
      payload = JSON.parse(body)
      payload["error"].is_a?(Hash) ? payload["error"]["message"] : payload["error"]
    rescue JSON::ParserError
      nil
    end

    def retryable_response?(response)
      response.is_a?(Net::HTTPTooManyRequests) || response.is_a?(Net::HTTPServerError)
    end

    def tts_open_timeout
      env_timeout("TTS_OPEN_TIMEOUT", default: 5)
    end

    def tts_read_timeout
      env_timeout("TTS_READ_TIMEOUT", default: 300)
    end

    def tts_write_timeout
      env_timeout("TTS_WRITE_TIMEOUT", default: 30)
    end

    def env_timeout(key, default:)
      value = ENV[key].to_i
      value.positive? ? value : default
    end
  end
end
