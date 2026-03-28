require "digest"

module Tts
  class GenerateService
    MAX_ATTEMPTS = 3

    class << self
      def call(note:, note_revision:, text:, language:, voice:, provider_name:, model: nil, format: "mp3", settings: {})
        raise Error, "Nenhum texto para gerar audio." if text.to_s.blank?

        text = strip_markup(text)

        provider_name = provider_name.to_s
        unless ProviderRegistry.available_provider_names.include?(provider_name)
          raise ProviderUnavailableError, "Provider TTS '#{provider_name}' nao disponivel."
        end

        # Default voice to first available if blank
        if voice.blank?
          available_voices = ProviderRegistry.voices_for(provider_name, language: language)
          voice = available_voices.first.to_s
          raise Error, "Nenhuma voz disponivel para #{provider_name} (#{language})." if voice.blank?
        end

        text_sha256 = Digest::SHA256.hexdigest(text)
        settings_hash = Digest::SHA256.hexdigest(settings.sort.to_json)

        cached = NoteTtsAsset.find_cached(
          text_sha256: text_sha256,
          language: language,
          voice: voice,
          provider: provider_name,
          model: model,
          settings_hash: settings_hash
        )

        return {tts_asset: cached, ai_request: nil, cached: true} if cached&.ready?

        tts_asset = note_revision.note_tts_assets.create!(
          language: language,
          voice: voice,
          provider: provider_name,
          model: model,
          format: format,
          text_sha256: text_sha256,
          settings_hash: settings_hash,
          is_active: true
        )

        ai_request = note_revision.ai_requests.create!(
          provider: provider_name,
          requested_provider: provider_name,
          capability: "tts",
          status: "queued",
          model: model,
          attempts_count: 0,
          max_attempts: MAX_ATTEMPTS,
          input_text: text,
          prompt_summary: "TTS #{provider_name} #{language} #{voice}",
          metadata: {
            "tts_asset_id" => tts_asset.id,
            "note_id" => note.id,
            "language" => language,
            "voice" => voice,
            "format" => format,
            "settings" => settings
          }
        )

        GenerateJob.perform_later(ai_request.id)

        {tts_asset: tts_asset, ai_request: ai_request, cached: false}
      end

      private

      # Minimal cleanup — text arrives pre-rendered from the preview pane
      # (innerText), so markdown/wikilink syntax is already stripped.
      # We normalize whitespace and convert line breaks to sentence breaks
      # so TTS providers (Kokoro etc.) produce natural pauses between
      # headings, paragraphs, and list items.
      def strip_markup(text)
        text = text.to_s
        text = text.gsub(/[^\S\n]+/, " ")                   # spaces/tabs → single space
        text = text.gsub(/\n{3,}/, "\n\n")                   # 3+ newlines → double
        # Convert line breaks to sentence breaks for natural TTS pauses.
        # Add period only when line doesn't already end with punctuation.
        text = text.gsub(/([^.!?:;\n])\s*\n+\s*/) { "#{$1}. " }
        text = text.gsub(/([.!?:;])\s*\n+\s*/) { "#{$1} " }
        text = text.strip
        text
      end
    end
  end
end
