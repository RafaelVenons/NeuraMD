require "json"
require "net/http"
require "uri"
require_relative "error"
require_relative "result"

module Ai
  class BaseProvider
    attr_reader :name, :model, :base_url, :api_key

    def initialize(name:, model:, base_url:, api_key: nil)
      @name = name
      @model = model
      @base_url = base_url
      @api_key = api_key
    end

    private

    def post_json(url, headers:, body:)
      uri = URI.parse(url)
      request = Net::HTTP::Post.new(uri)
      headers.each { |key, value| request[key] = value }
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(body)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = provider_open_timeout
      http.read_timeout = provider_read_timeout
      http.write_timeout = provider_write_timeout if http.respond_to?(:write_timeout=)
      response = http.request(request)

      payload = JSON.parse(response.body.presence || "{}")
      return payload if response.is_a?(Net::HTTPSuccess)

      message = extract_error(payload) || "Falha na chamada ao provider #{name}."
      error_class = retryable_response?(response) ? TransientRequestError : RequestError
      raise error_class, message
    rescue JSON::ParserError
      raise RequestError, "Resposta invalida do provider #{name}."
    rescue SocketError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
      raise TransientRequestError, "#{name} indisponivel: #{e.message}"
    end

    def extract_error(payload)
      payload["error"].is_a?(Hash) ? payload["error"]["message"] : payload["error"]
    end

    def retryable_response?(response)
      response.is_a?(Net::HTTPTooManyRequests) || response.is_a?(Net::HTTPServerError)
    end

    def provider_open_timeout
      env_timeout(provider_timeout_key("OPEN_TIMEOUT"), default: 5)
    end

    def provider_read_timeout
      env_timeout(provider_timeout_key("READ_TIMEOUT"), default: default_read_timeout)
    end

    def provider_write_timeout
      env_timeout(provider_timeout_key("WRITE_TIMEOUT"), default: 30)
    end

    def env_timeout(key, default:)
      value = ENV[key].to_i
      value.positive? ? value : default
    end

    def provider_timeout_key(suffix)
      return "#{name.upcase.tr("-", "_")}_#{suffix}" if name.start_with?("ollama")

      case name
      when "anthropic"
        "ANTHROPIC_#{suffix}"
      when "openai", "azure_openai"
        "OPENAI_#{suffix}"
      else
        "AI_PROVIDER_#{suffix}"
      end
    end

    def default_read_timeout
      name.start_with?("ollama") ? 7200 : 180
    end
  end
end
