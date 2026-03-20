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
      response = http.request(request)

      payload = JSON.parse(response.body.presence || "{}")
      return payload if response.is_a?(Net::HTTPSuccess)

      raise RequestError, extract_error(payload) || "Falha na chamada ao provider #{name}."
    rescue JSON::ParserError
      raise RequestError, "Resposta invalida do provider #{name}."
    rescue SocketError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
      raise RequestError, "#{name} indisponivel: #{e.message}"
    end

    def extract_error(payload)
      payload["error"].is_a?(Hash) ? payload["error"]["message"] : payload["error"]
    end
  end
end
