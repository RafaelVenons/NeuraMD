module Ai
  class OllamaProvider < BaseProvider
    def review(capability:, text:, language:)
      payload = post_json(
        "#{base_url}/api/chat",
        headers: {},
        body: {
          model: model,
          stream: false,
          messages: [
            { role: "system", content: PromptBuilder.system_prompt(capability:, language:) },
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
