require "base64"

module Tts
  class GeminiProvider < BaseProvider
    DEFAULT_MODEL = "gemini-2.5-flash-preview-tts"

    def synthesize(text:, voice:, language:, model:, format:, settings:)
      resolved_model = model.presence || DEFAULT_MODEL
      url = "#{base_url}/v1beta/models/#{resolved_model}:generateContent"
      headers = {"x-goog-api-key" => api_key}
      body = {
        contents: [{parts: [{text: text}]}],
        generationConfig: {
          responseModalities: ["AUDIO"],
          speechConfig: {
            voiceConfig: {
              prebuiltVoiceConfig: {voiceName: voice}
            }
          }
        }
      }

      response = post_json(url, headers: headers, body: body)
      audio_data = extract_audio(response)
      Result.new(audio_data: audio_data, content_type: "audio/wav")
    end

    private

    def extract_audio(response)
      parts = response.dig("candidates", 0, "content", "parts") || []
      audio_part = parts.find { |p| p.dig("inlineData", "data") }
      raise RequestError, "Gemini nao retornou audio data." unless audio_part

      Base64.decode64(audio_part["inlineData"]["data"])
    end

    def post_json(url, headers:, body:)
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

      payload = JSON.parse(response.body.presence || "{}")
      return payload if response.is_a?(Net::HTTPSuccess)

      message = payload.dig("error", "message") || "Falha na chamada ao provider #{name}."
      error_class = retryable_response?(response) ? TransientRequestError : RequestError
      raise error_class, message
    rescue JSON::ParserError
      raise RequestError, "Resposta invalida do provider #{name}."
    rescue SocketError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
      raise TransientRequestError, "#{name} indisponivel: #{e.message}"
    end
  end
end
