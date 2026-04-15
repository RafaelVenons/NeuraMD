require "rails_helper"

RSpec.describe AiRequest, type: :model do
  around do |example|
    original_env = %w[
      OLLAMA_RUNNING_STUCK_AFTER
      OLLAMA_QUEUED_STUCK_AFTER
      OLLAMA_RETRY_GRACE_PERIOD
    ].index_with { |key| ENV[key] }

    example.run
  ensure
    original_env.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  it "broadcasts a dashboard refresh when the request changes" do
    ai_request = create(:ai_request)
    clear_enqueued_jobs
    clear_performed_jobs

    streams = capture_turbo_stream_broadcasts("ai_requests_dashboard") do
      perform_enqueued_jobs do
        ai_request.update!(status: "running", started_at: Time.current)
      end
    end

    expect(streams.size).to eq(1)
    expect(streams.first["action"]).to eq("refresh")
  end

  it "broadcasts note request updates for the editor stream" do
    ai_request = create(:ai_request)
    clear_enqueued_jobs
    clear_performed_jobs

    streams = capture_turbo_stream_broadcasts([ai_request.note_revision.note, :ai_requests]) do
      perform_enqueued_jobs do
        ai_request.update!(status: "running", started_at: Time.current)
      end
    end

    expect(streams.size).to eq(1)
    expect(streams.first["action"]).to eq("dispatch_event")
    expect(streams.first["target"]).to eq("editor-root")
    expect(streams.first["name"]).to eq("ai-request:update")
  end

  it "does not consider slow ollama executions stuck before the provider-specific window" do
    ENV["OLLAMA_RUNNING_STUCK_AFTER"] = "10800"
    request = create(:ai_request, provider: "ollama", status: "running", started_at: 2.hours.ago)

    expect(request.stuck?).to be(false)
    expect(request.stuck_reason).to be_nil
  end

  it "does not consider queued ollama requests stuck before the provider-specific queue window" do
    ENV["OLLAMA_QUEUED_STUCK_AFTER"] = "21600"
    request = create(:ai_request, provider: "ollama", status: "queued", created_at: 2.hours.ago)

    expect(request.stuck?).to be(false)
    expect(request.stuck_reason).to be_nil
  end

  it "still flags very old ollama retries as delayed after the provider-specific grace period" do
    ENV["OLLAMA_RETRY_GRACE_PERIOD"] = "600"
    request = create(:ai_request, provider: "ollama", status: "retrying", next_retry_at: 20.minutes.ago)

    expect(request.stuck?).to be(true)
    expect(request.stuck_reason).to eq("Retry atrasado")
  end

  it "exposes remote duration and long-job hints for ollama requests" do
    request = create(:ai_request, provider: "ollama", status: "running", started_at: 2.minutes.ago)

    expect(request.duration_human).to match(/2min/)
    expect(request.remote_long_job?).to be(true)
    expect(request.remote_status_hint).to eq("Job remoto longo no Bazzite. Pode fechar e voltar depois.")
    expect(request.realtime_payload).to include(
      duration_human: request.duration_human,
      remote_long_job: true,
      remote_hint: "Job remoto longo no Bazzite. Pode fechar e voltar depois."
    )
  end

  it "includes translated note navigation in the realtime payload when available" do
    source_note = create(:note, :with_head_revision)
    translated_note = create(:note, :with_head_revision, title: "Translated")
    request = create(
      :ai_request,
      note_revision: source_note.head_revision,
      capability: "translate",
      metadata: {
        "language" => "pt-BR",
        "target_language" => "en-US",
        "translated_note_id" => translated_note.id
      }
    )

    expect(request.realtime_payload).to include(
      translated_note_id: translated_note.id,
      translated_note_title: "Translated",
      translated_note_slug: translated_note.slug
    )
  end

  it "includes TTS-specific fields in realtime_payload for tts capability" do
    note = create(:note, :with_head_revision)
    tts_asset = create(:note_tts_asset,
      note_revision: note.head_revision,
      provider: "kokoro",
      voice: "af_bella",
      language: "pt-BR",
      format: "mp3",
      duration_ms: 4500
    )
    # Attach a fake audio so asset is "ready"
    tts_asset.audio.attach(
      io: StringIO.new("fake-audio"),
      filename: "test.mp3",
      content_type: "audio/mpeg"
    )

    request = create(:ai_request,
      note_revision: note.head_revision,
      capability: "tts",
      provider: "kokoro",
      metadata: {
        "tts_asset_id" => tts_asset.id,
        "voice" => "af_bella",
        "language" => "pt-BR",
        "format" => "mp3"
      }
    )

    payload = request.realtime_payload
    expect(payload).to include(
      tts_voice: "af_bella",
      tts_language: "pt-BR",
      tts_format: "mp3",
      tts_audio_ready: true,
      tts_duration_ms: 4500
    )
  end

  it "handles missing TTS asset gracefully in realtime_payload" do
    request = create(:ai_request,
      capability: "tts",
      provider: "kokoro",
      metadata: {
        "tts_asset_id" => SecureRandom.uuid,
        "voice" => "af_bella",
        "language" => "pt-BR",
        "format" => "mp3"
      }
    )

    payload = request.realtime_payload
    expect(payload).to include(
      tts_voice: "af_bella",
      tts_language: "pt-BR",
      tts_format: "mp3",
      tts_audio_ready: false,
      tts_duration_ms: nil
    )
  end
end
