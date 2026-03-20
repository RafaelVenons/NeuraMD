module Ai
  class AnthropicProvider < BaseProvider
    def review(capability:, text:, language:)
      payload = post_json(
        "#{base_url}/messages",
        headers: {
          "x-api-key" => api_key.to_s,
          "anthropic-version" => ENV.fetch("ANTHROPIC_VERSION", "2023-06-01")
        },
        body: {
          model: model,
          max_tokens: 4096,
          system: PromptBuilder.system_prompt(capability:, language:),
          messages: [{ role: "user", content: text }]
        }
      )

      content = Array(payload["content"]).filter_map { |part| part["text"] }.join
      raise RequestError, "Resposta vazia do provider #{name}." if content.blank?

      Result.new(
        content: content,
        provider: name,
        model: model,
        tokens_in: payload.dig("usage", "input_tokens"),
        tokens_out: payload.dig("usage", "output_tokens")
      )
    end
  end
end
