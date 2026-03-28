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
        {"word" => "com", "start" => 0.45, "end" => 0.75},
        {"word" => "erro", "start" => 0.8, "end" => 1.2}
      ],
      "duration_s" => 1.2
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

  it "shows karaoke words in preview when alignment data is present" do
    # Create a ready asset with alignment data
    asset = create(:note_tts_asset, :with_audio,
      note_revision: head_revision,
      alignment_data: alignment_data,
      alignment_status: "succeeded")

    visit note_path(note.slug)

    # Player should show with karaoke toggle visible
    expect(page).to have_css("[data-tts-target='player']:not(.hidden)", wait: 10)
    expect(page).to have_css("[data-tts-target='karaokeToggle']:not(.hidden)")

    # Karaoke auto-activates — verify words are highlighted in the preview pane
    within("[data-preview-target='output']") do
      expect(page).to have_css(".karaoke-word", minimum: 1, wait: 10)
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

  it "highlights the active karaoke word with white background at a known MFA time" do
    # Create a ready asset with alignment data
    create(:note_tts_asset, :with_audio,
      note_revision: head_revision,
      alignment_data: alignment_data,
      alignment_status: "succeeded")

    visit note_path(note.slug)

    # Wait for player to show (confirms fetchStatus ran and asset loaded)
    expect(page).to have_css("[data-tts-target='player']:not(.hidden)", wait: 10)

    # Programmatically inject karaoke spans and activate highlighting.
    # Set _words directly (not alignmentValue) to avoid Stimulus MutationObserver
    # double-firing alignmentValueChanged which would deactivate the spans.
    page.execute_script(<<~JS)
      (() => {
        const el = document.querySelector("[data-controller~='karaoke']");
        const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, "karaoke");
        ctrl._words = #{alignment_data["words"].to_json};
        ctrl._injected = false;
        ctrl._retryCount = 0;
        ctrl.activate();
      })()
    JS

    # Verify karaoke spans were injected into the preview pane
    within("[data-preview-target='output']") do
      expect(page).to have_css(".karaoke-word", minimum: 1, wait: 5)
    end

    # Disable CSS transitions so computed styles reflect final values immediately
    page.execute_script("document.querySelectorAll('.karaoke-word').forEach(el => el.style.transition = 'none')")

    # Simulate audio at t=0.2s — should highlight "Trecho" (start=0.0, end=0.4)
    page.execute_script(<<~JS)
      (() => {
        const el = document.querySelector("[data-controller~='karaoke']");
        const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, "karaoke");
        ctrl._highlightWord(0);
        ctrl._currentIndex = 0;
      })()
    JS

    # Verify "Trecho" is highlighted with white background
    within("[data-preview-target='output']") do
      active_word = find(".karaoke-active", wait: 3)
      expect(active_word.text).to eq("Trecho")

      bg_color = page.evaluate_script(<<~JS)
        (() => { return getComputedStyle(document.querySelector('.karaoke-active')).backgroundColor; })()
      JS
      expect(bg_color).to eq("rgb(255, 255, 255)")
    end

    # Simulate time advancing to t=0.5s — should highlight "com" (start=0.45, end=0.6)
    page.execute_script(<<~JS)
      (() => {
        const el = document.querySelector("[data-controller~='karaoke']");
        const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, "karaoke");
        ctrl._highlightWord(1);
        ctrl._currentIndex = 1;
      })()
    JS

    within("[data-preview-target='output']") do
      active_word = find(".karaoke-active", wait: 3)
      expect(active_word.text).to eq("com")

      # Only one word should be active at a time
      expect(page).to have_css(".karaoke-active", count: 1)
    end
  end

  it "groups short-duration words so they highlight together" do
    # Alignment with very short words: "é" (30ms) and "uma" (70ms) are too fast
    # to be visible individually. They should be grouped and highlighted together.
    short_alignment = {
      "words" => [
        {"word" => "Saúde",  "start" => 0.0,  "end" => 0.4},
        {"word" => "é",      "start" => 0.9,  "end" => 0.93},   # 30ms
        {"word" => "uma",    "start" => 0.93, "end" => 1.0},    # 70ms
        {"word" => "prioridade", "start" => 1.05, "end" => 1.6}
      ],
      "duration_s" => 1.6
    }

    head_revision.update!(content_markdown: "Saúde é uma prioridade.")

    create(:note_tts_asset, :with_audio,
      note_revision: head_revision,
      alignment_data: short_alignment,
      alignment_status: "succeeded")

    visit note_path(note.slug)
    expect(page).to have_css("[data-tts-target='player']:not(.hidden)", wait: 10)

    page.execute_script(<<~JS)
      (() => {
        const el = document.querySelector("[data-controller~='karaoke']");
        const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, "karaoke");
        ctrl._words = #{short_alignment["words"].to_json};
        ctrl._injected = false;
        ctrl._retryCount = 0;
        ctrl.activate();
      })()
    JS

    within("[data-preview-target='output']") do
      expect(page).to have_css(".karaoke-word", minimum: 4, wait: 5)
    end

    page.execute_script("document.querySelectorAll('.karaoke-word').forEach(el => el.style.transition = 'none')")

    # Simulate time at t=0.92 — inside "é" (30ms word).
    # Without grouping, this word would flash too fast to see.
    # "é" + "uma" = 100ms (still < 200ms), so they get merged with next word "prioridade".
    # The full group "é uma prioridade" highlights together.
    page.execute_script(<<~JS)
      (() => {
        const el = document.querySelector("[data-controller~='karaoke']");
        const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, "karaoke");
        const idx = ctrl._findWordIndex(0.92);
        ctrl._highlightWord(idx);
        ctrl._currentIndex = idx;
      })()
    JS

    within("[data-preview-target='output']") do
      active_words = all(".karaoke-active", wait: 3)
      expect(active_words.length).to eq(3)
      expect(active_words.map(&:text)).to eq(["é", "uma", "prioridade."])
    end

    # "Saúde" (400ms) should highlight alone — it's long enough
    page.execute_script(<<~JS)
      (() => {
        const el = document.querySelector("[data-controller~='karaoke']");
        const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, "karaoke");
        const idx = ctrl._findWordIndex(0.2);
        ctrl._highlightWord(idx);
        ctrl._currentIndex = idx;
      })()
    JS

    within("[data-preview-target='output']") do
      active_words = all(".karaoke-active", wait: 3)
      expect(active_words.length).to eq(1)
      expect(active_words.first.text).to eq("Saúde")
    end
  end

  it "groups an isolated short word with its next neighbor" do
    # "da" (90ms) is isolated between two long words — no gap to expand into.
    # It must merge with the next word "humanidade" so it's visible.
    isolated_alignment = {
      "words" => [
        {"word" => "culturas", "start" => 1.98, "end" => 2.46},
        {"word" => "da",       "start" => 2.46, "end" => 2.55},  # 90ms, no gaps
        {"word" => "humanidade", "start" => 2.55, "end" => 3.19}
      ],
      "duration_s" => 3.19
    }

    head_revision.update!(content_markdown: "culturas da humanidade")

    create(:note_tts_asset, :with_audio,
      note_revision: head_revision,
      alignment_data: isolated_alignment,
      alignment_status: "succeeded")

    visit note_path(note.slug)
    expect(page).to have_css("[data-tts-target='player']:not(.hidden)", wait: 10)

    page.execute_script(<<~JS)
      (() => {
        const el = document.querySelector("[data-controller~='karaoke']");
        const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, "karaoke");
        ctrl._words = #{isolated_alignment["words"].to_json};
        ctrl._injected = false;
        ctrl._retryCount = 0;
        ctrl.activate();
      })()
    JS

    within("[data-preview-target='output']") do
      expect(page).to have_css(".karaoke-word", minimum: 3, wait: 5)
    end

    page.execute_script("document.querySelectorAll('.karaoke-word').forEach(el => el.style.transition = 'none')")

    # Simulate time at t=2.50 — inside "da" (90ms, no gaps around it).
    # "da" should be grouped with "humanidade" and both highlight.
    page.execute_script(<<~JS)
      (() => {
        const el = document.querySelector("[data-controller~='karaoke']");
        const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, "karaoke");
        const idx = ctrl._findWordIndex(2.50);
        ctrl._highlightWord(idx);
        ctrl._currentIndex = idx;
      })()
    JS

    within("[data-preview-target='output']") do
      active_words = all(".karaoke-active", wait: 3)
      expect(active_words.length).to eq(2)
      expect(active_words.map(&:text)).to eq(["da", "humanidade"])
    end

    # "culturas" (480ms) should highlight alone
    page.execute_script(<<~JS)
      (() => {
        const el = document.querySelector("[data-controller~='karaoke']");
        const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, "karaoke");
        const idx = ctrl._findWordIndex(2.2);
        ctrl._highlightWord(idx);
        ctrl._currentIndex = idx;
      })()
    JS

    within("[data-preview-target='output']") do
      active_words = all(".karaoke-active", wait: 3)
      expect(active_words.length).to eq(1)
      expect(active_words.first.text).to eq("culturas")
    end
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
