require "rails_helper"

RSpec.describe "TTS player", type: :system do
  let!(:user) { create(:user) }
  let!(:note) { create(:note, :with_head_revision) }
  let!(:head_revision) { note.reload.head_revision }

  around do |example|
    original_env = %w[
      TTS_KOKORO_BASE_URL
    ].index_with { |key| ENV[key] }

    ENV["TTS_KOKORO_BASE_URL"] = "http://AIrch.local:8880"

    example.run
  ensure
    original_env.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  let(:audio_bytes) { "\xFF\xFB\x90\x04fake-tts-audio".b }
  let(:alignment_data) do
    {
      "words" => [
        {"word" => "Trecho", "start" => 0.0, "end" => 0.4},
        {"word" => "com", "start" => 0.45, "end" => 0.6},
        {"word" => "erro", "start" => 0.65, "end" => 1.0}
      ],
      "duration_s" => 1.0
    }
  end

  before do
    head_revision.update!(content_markdown: "Trecho com erro.")

    # Stub TTS provider to return fake audio immediately
    fake_result = Tts::Result.new(
      audio_data: audio_bytes,
      content_type: "audio/mpeg",
      duration_ms: 1000
    )
    allow_any_instance_of(Tts::KokoroProvider).to receive(:synthesize).and_return(fake_result)

    # Stub MFA alignment — no real SSH
    allow(Mfa::AlignService).to receive(:call) do |asset|
      asset.update!(
        alignment_data: alignment_data,
        alignment_status: "succeeded"
      )
    end

    sign_in_via_ui user
  end

  it "opens dialog and submits generation request" do
    visit note_path(note.slug)

    # Open TTS dialog
    find("[data-tts-target='generateBtn']").click
    expect(page).to have_css("[data-tts-target='dialog']:not(.hidden)")

    # Click generate — job is enqueued (not executed in test env)
    find("[data-tts-target='dialog'] [data-action='click->tts#generate']").click

    # Dialog closes and spinner shows while polling
    expect(page).to have_no_css("[data-tts-target='dialog']:not(.hidden)", wait: 5)
    expect(page).to have_text("Criando Audio...")
  end

  it "shows karaoke toggle when alignment data is present" do
    # Create a ready asset with alignment data
    asset = create(:note_tts_asset, :with_audio,
      note_revision: head_revision,
      alignment_data: alignment_data,
      alignment_status: "succeeded")

    visit note_path(note.slug)

    # Player should show with karaoke toggle visible
    expect(page).to have_css("[data-tts-target='player']:not(.hidden)", wait: 10)
    expect(page).to have_css("[data-tts-target='karaokeToggle']:not(.hidden)")

    # Click karaoke toggle
    find("[data-tts-target='karaokeToggle']").click
    expect(page).to have_css("[data-tts-target='karaokePanel']:not(.hidden)")

    # Verify karaoke words are rendered
    within("[data-karaoke-target='text']") do
      expect(page).to have_css(".karaoke-word", count: 3)
      expect(page).to have_text("Trecho")
      expect(page).to have_text("com")
      expect(page).to have_text("erro")
    end
  end

  it "shows stale audio notice when note is edited after TTS" do
    # Create a ready asset on the head revision
    create(:note_tts_asset, :with_audio, note_revision: head_revision)

    visit note_path(note.slug)
    expect(page).to have_css("[data-tts-target='player']:not(.hidden)", wait: 10)

    # Edit the note content (triggers codemirror:change)
    editor = find("[data-controller~='codemirror']")
    editor.click
    page.send_keys("Novo texto adicionado")

    # Player should hide and stale notice should appear
    expect(page).to have_css("[data-tts-target='staleNotice']:not(.hidden)", wait: 5)
    expect(page).to have_text("Revisão anterior possui audio")
  end

  it "loads stale audio when clicking the notice" do
    # Create a checkpoint with audio, then a newer checkpoint without audio
    old_revision = create(:note_revision, note: note, content_markdown: "Texto antigo")
    create(:note_tts_asset, :with_audio, note_revision: old_revision)

    # Update head to a newer revision without audio
    new_revision = create(:note_revision, note: note, content_markdown: "Texto novo editado")
    note.update!(head_revision_id: new_revision.id)

    visit note_path(note.slug)

    # Should show stale notice (old revision has audio, current doesn't)
    expect(page).to have_css("[data-tts-target='staleNotice']:not(.hidden)", wait: 10)

    # Click the notice to load old audio
    find("[data-tts-target='staleNotice']").click
    expect(page).to have_css("[data-tts-target='player']:not(.hidden)", wait: 5)
  end

  it "opens library tab in dialog" do
    create(:note_tts_asset, :with_audio, note_revision: head_revision)

    visit note_path(note.slug)

    # Open dialog and switch to library tab
    find("[data-tts-target='generateBtn']").click
    find("[data-tts-target='libraryTab']").click

    expect(page).to have_css("[data-tts-target='libraryPanel']:not(.hidden)")
    expect(page).to have_css("[data-tts-target='libraryList']")
  end
end
