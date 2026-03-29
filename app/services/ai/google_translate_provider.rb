require "json"
require "net/http"
require "uri"
require_relative "error"
require_relative "result"

module Ai
  class GoogleTranslateProvider < BaseProvider
    WIKILINK_PATTERN = /\[\[[^\]]*\]\]/
    PLACEHOLDER_CHAR = "\u0000"

    def review(capability:, text:, language:, target_language: nil)
      raise RequestError, "Google Translate suporta somente tradução." unless capability.to_s == "translate"
      raise RequestError, "Texto vazio para tradução." if text.to_s.strip.blank?
      raise RequestError, "Idioma alvo obrigatório para tradução." if target_language.to_s.strip.blank?

      source_lang = normalize_language_code(language)
      target_lang = normalize_language_code(target_language)

      wikilinks = []
      sanitized_text = text.gsub(WIKILINK_PATTERN) do |match|
        idx = wikilinks.size
        wikilinks << match
        "#{PLACEHOLDER_CHAR}WL#{idx}#{PLACEHOLDER_CHAR}"
      end

      translated = fetch_translation(sanitized_text, source_lang, target_lang)
      raise RequestError, "Texto traduzido vazio do Google Translate." if translated.to_s.strip.blank?

      wikilinks.each_with_index do |wl, idx|
        translated.gsub!("#{PLACEHOLDER_CHAR}WL#{idx}#{PLACEHOLDER_CHAR}", wl)
      end

      Result.new(
        content: translated,
        provider: name,
        model: model,
        tokens_in: nil,
        tokens_out: nil
      )
    end

    private

    def fetch_translation(text, source_lang, target_lang)
      uri = URI("#{base_url}/translate_a/single")
      uri.query = URI.encode_www_form(
        client: "gtx",
        sl: source_lang,
        tl: target_lang,
        dt: "t",
        q: text
      )

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 30

      request = Net::HTTP::Get.new(uri)
      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        error_class = response.is_a?(Net::HTTPTooManyRequests) || response.is_a?(Net::HTTPServerError) ? TransientRequestError : RequestError
        raise error_class, "Google Translate retornou HTTP #{response.code}."
      end

      payload = JSON.parse(response.body)
      sentences = Array(payload[0])
      sentences.filter_map { |s| s[0] }.join
    rescue JSON::ParserError
      raise RequestError, "Resposta invalida do Google Translate."
    rescue SocketError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
      raise TransientRequestError, "Google Translate indisponivel: #{e.message}"
    end

    def normalize_language_code(language)
      return "auto" if language.to_s.strip.blank?
      language.to_s.split(/[-_]/).first.downcase
    end
  end
end
