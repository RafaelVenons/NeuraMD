module Ai
  class OllamaProvider < BaseProvider
    class << self
      def available_models(base_url:, open_timeout: 3, read_timeout: 5)
        uri = URI.parse("#{base_url}/api/tags")
        request = Net::HTTP::Get.new(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = open_timeout
        http.read_timeout = read_timeout
        response = http.request(request)
        return [] unless response.is_a?(Net::HTTPSuccess)

        payload = JSON.parse(response.body.presence || "{}")
        Array(payload["models"])
          .map { |entry| entry.is_a?(Hash) ? entry["name"] : nil }
          .compact
          .reject { |name| name.include?("embed") }
          .uniq
      rescue JSON::ParserError, SocketError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout
        []
      end
    end

    def review(capability:, text:, language:, target_language: nil)
      payload = post_json(
        "#{base_url}/api/chat",
        headers: {},
        body: {
          model: model,
          stream: false,
          messages: [
            { role: "system", content: PromptBuilder.system_prompt(capability:, language:, target_language:) },
            { role: "user", content: text }
          ],
          options: { temperature: 0.2 }
        }
      )

      content = payload.dig("message", "content").to_s
      raise RequestError, "Resposta vazia do provider #{name}." if content.blank?

      Result.new(
        content: content,
        provider: name,
        model: model,
        tokens_in: payload["prompt_eval_count"],
        tokens_out: payload["eval_count"]
      )
    end
  end
end
