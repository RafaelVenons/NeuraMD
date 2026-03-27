module Tts
  class FishAudioProvider < BaseProvider
    CONTENT_TYPES = {
      "mp3" => "audio/mpeg",
      "wav" => "audio/wav",
      "opus" => "audio/opus"
    }.freeze

    def synthesize(text:, voice:, language:, model:, format:, settings:)
      url = "#{base_url}/v1/tts"
      headers = {
        "Authorization" => "Bearer #{api_key}"
      }
      body = {
        text: text,
        reference_id: voice,
        format: format
      }

      audio_data = post_binary(url, headers: headers, body: body)
      Result.new(audio_data: audio_data, content_type: CONTENT_TYPES.fetch(format, "audio/mpeg"))
    end
  end
end
