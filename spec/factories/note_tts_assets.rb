FactoryBot.define do
  factory :note_tts_asset do
    note_revision
    language { "pt-BR" }
    voice { "pf_dora" }
    provider { "kokoro" }
    model { nil }
    format { "mp3" }
    text_sha256 { Digest::SHA256.hexdigest("sample text") }
    settings_hash { Digest::SHA256.hexdigest("{}") }
    is_active { true }

    trait :with_audio do
      after(:create) do |asset|
        asset.audio.attach(
          io: StringIO.new("\xFF\xFB\x90\x00".b),
          filename: "tts_#{asset.id}.mp3",
          content_type: "audio/mpeg"
        )
      end
    end

    trait :inactive do
      is_active { false }
    end

    trait :elevenlabs do
      provider { "elevenlabs" }
      voice { "21m00Tcm4TlvDq8ikWAM" }
      model { "eleven_multilingual_v2" }
    end

    trait :gemini do
      provider { "gemini" }
      voice { "Kore" }
      model { "gemini-2.5-flash-preview-tts" }
    end

    trait :fish_audio do
      provider { "fish_audio" }
      voice { "ref-123" }
    end
  end
end
