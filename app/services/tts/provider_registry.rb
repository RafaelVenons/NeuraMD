require_relative "error"

module Tts
  class ProviderRegistry
    PROVIDERS = %w[elevenlabs fish_audio gemini kokoro].freeze
    FALSE_VALUES = %w[0 false off no].freeze

    VOICE_CATALOG = {
      "kokoro" => {
        "pt-BR" => %w[pf_dora pm_alex pm_santa],
        "en-US" => %w[af_heart af_bella af_nicole am_adam am_michael],
        "en-GB" => %w[bf_emma bf_isabella bm_george bm_lewis],
        "zh-CN" => %w[zf_xiaobei zf_xiaoni zf_xiaoxiao zm_yunjian zm_yunxi],
        "ja-JP" => %w[jf_alpha jf_gongitsune jm_kumo],
        "ko-KR" => %w[kf_yuha km_yongsu],
        "es-ES" => %w[ef_dora em_alex],
        "fr-FR" => %w[ff_siwis],
        "it-IT" => %w[if_sara im_nicola],
        "hi-IN" => %w[hf_alpha hf_beta hm_omega hm_psi]
      },
      "elevenlabs" => {
        "_default" => %w[21m00Tcm4TlvDq8ikWAM EXAVITQu4vr4xnSDxMaL onwK4e9ZLuTAKqWW03F9 pNInz6obpgDQGcFmaJgB]
      },
      "fish_audio" => {
        "_default" => %w[]
      },
      "gemini" => {
        "_default" => %w[Kore Charon Fenrir Aoede Puck]
      }
    }.freeze

    DEFAULT_BASE_URLS = {
      "elevenlabs" => "https://api.elevenlabs.io",
      "fish_audio" => "https://api.fish.audio",
      "gemini" => "https://generativelanguage.googleapis.com",
      "kokoro" => "http://bazzite.local:8880"
    }.freeze

    class << self
      def enabled?
        return false if FALSE_VALUES.include?(ENV["TTS_ENABLED"].to_s.downcase)

        available_provider_names.any?
      end

      def available_provider_names
        PROVIDERS.select { |name| configured?(name) }
      end

      def build(provider_name)
        name = provider_name.to_s
        raise ProviderUnavailableError, "Provider TTS '#{name}' nao disponivel." unless available_provider_names.include?(name)

        config = provider_config(name)

        case name
        when "elevenlabs"
          ElevenlabsProvider.new(**config)
        when "fish_audio"
          FishAudioProvider.new(**config)
        when "gemini"
          GeminiProvider.new(**config)
        when "kokoro"
          KokoroProvider.new(**config)
        else
          raise ProviderUnavailableError, "Provider TTS '#{name}' nao suportado."
        end
      end

      def status
        {
          enabled: enabled?,
          available_providers: available_provider_names,
          providers: available_provider_names.map { |name|
            {name: name, label: provider_label(name)}
          }
        }
      end

      def voices_for(provider_name, language:)
        catalog = VOICE_CATALOG[provider_name.to_s] || {}
        catalog[language] || catalog["_default"] || []
      end

      private

      def configured?(name)
        case name
        when "elevenlabs"
          ENV["TTS_ELEVENLABS_API_KEY"].present?
        when "fish_audio"
          ENV["TTS_FISH_AUDIO_API_KEY"].present?
        when "gemini"
          ENV["TTS_GEMINI_API_KEY"].present?
        when "kokoro"
          ENV["TTS_KOKORO_BASE_URL"].present?
        else
          false
        end
      end

      def provider_config(name)
        case name
        when "elevenlabs"
          {name: name, base_url: ENV["TTS_ELEVENLABS_BASE_URL"].presence || DEFAULT_BASE_URLS["elevenlabs"], api_key: ENV["TTS_ELEVENLABS_API_KEY"]}
        when "fish_audio"
          {name: name, base_url: ENV["TTS_FISH_AUDIO_BASE_URL"].presence || DEFAULT_BASE_URLS["fish_audio"], api_key: ENV["TTS_FISH_AUDIO_API_KEY"]}
        when "gemini"
          {name: name, base_url: ENV["TTS_GEMINI_BASE_URL"].presence || DEFAULT_BASE_URLS["gemini"], api_key: ENV["TTS_GEMINI_API_KEY"]}
        when "kokoro"
          {name: name, base_url: ENV["TTS_KOKORO_BASE_URL"].presence || DEFAULT_BASE_URLS["kokoro"]}
        end
      end

      def provider_label(name)
        {
          "elevenlabs" => "ElevenLabs",
          "fish_audio" => "Fish Audio",
          "gemini" => "Gemini",
          "kokoro" => "Kokoro (Local)"
        }[name] || name.humanize
      end
    end
  end
end
