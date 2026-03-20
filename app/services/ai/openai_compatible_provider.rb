module Ai
  class OpenaiCompatibleProvider < BaseProvider
    def review(capability:, text:, language:, target_language: nil)
      payload = post_json(
        endpoint_url,
        headers: request_headers,
        body: request_body(capability:, text:, language:, target_language:)
      )

      message = payload.dig("choices", 0, "message", "content")
      content = normalize_content(message)
      raise RequestError, "Resposta vazia do provider #{name}." if content.blank?

      Result.new(
        content: content,
        provider: name,
        model: model,
        tokens_in: payload.dig("usage", "prompt_tokens"),
        tokens_out: payload.dig("usage", "completion_tokens")
      )
    end

    private

    def endpoint_url
      if name == "azure_openai"
        version = ENV.fetch("AZURE_OPENAI_API_VERSION", "2024-10-21")
        "#{base_url}/openai/deployments/#{model}/chat/completions?api-version=#{version}"
      else
        "#{base_url}/chat/completions"
      end
    end

    def request_headers
      if name == "azure_openai"
        { "api-key" => api_key.to_s }
      else
        { "Authorization" => "Bearer #{api_key}" }
      end
    end

    def request_body(capability:, text:, language:, target_language:)
      body = {
        messages: [
          { role: "system", content: PromptBuilder.system_prompt(capability:, language:, target_language:) },
          { role: "user", content: text }
        ],
        temperature: 0.2
      }
      body[:model] = model unless name == "azure_openai"
      body
    end

    def normalize_content(message)
      return message if message.is_a?(String)
      return message.map { |part| part["text"] }.join if message.is_a?(Array)

      message.to_s
    end
  end
end
