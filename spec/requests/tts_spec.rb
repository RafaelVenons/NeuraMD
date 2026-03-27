require "rails_helper"

RSpec.describe "TTS", type: :request do
  let(:user) { create(:user) }
  let(:note) { create(:note) }
  let!(:revision) { create(:note_revision, note: note) }

  before { sign_in user }

  describe "GET /notes/:slug/tts_status" do
    it "returns TTS status with available providers" do
      allow(Tts::ProviderRegistry).to receive(:status).and_return(
        enabled: true,
        available_providers: %w[kokoro],
        providers: [{name: "kokoro", label: "Kokoro (Local)"}]
      )
      allow(Tts::ProviderRegistry).to receive(:voices_for).and_return(%w[pf_dora])

      get tts_status_note_path(note.slug)

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["enabled"]).to be true
      expect(json["available_providers"]).to eq(%w[kokoro])
    end

    it "includes active tts asset info when present" do
      asset = create(:note_tts_asset, :with_audio, note_revision: revision)
      note.update!(head_revision_id: revision.id)

      get tts_status_note_path(note.slug)

      json = response.parsed_body
      expect(json["active_asset"]).to be_present
      expect(json["active_asset"]["id"]).to eq(asset.id)
    end
  end

  describe "POST /notes/:slug/tts_generate" do
    before do
      allow(Tts::ProviderRegistry).to receive(:available_provider_names).and_return(%w[kokoro])
      allow(Tts::GenerateJob).to receive(:perform_later)
    end

    it "creates a TTS generation request" do
      post tts_generate_note_path(note.slug), params: {
        text: "Hello world",
        language: "en-US",
        voice: "af_heart",
        provider: "kokoro",
        format: "mp3"
      }

      expect(response).to have_http_status(:accepted)
      json = response.parsed_body
      expect(json["tts_asset_id"]).to be_present
      expect(json["ai_request_id"]).to be_present
      expect(json["cached"]).to be false
    end

    it "returns cached asset when available" do
      sha = Digest::SHA256.hexdigest("Hello world")
      settings_sha = Digest::SHA256.hexdigest({}.sort.to_json)
      create(:note_tts_asset, :with_audio,
        note_revision: revision,
        text_sha256: sha, language: "en-US", voice: "af_heart",
        provider: "kokoro", model: nil, settings_hash: settings_sha)

      post tts_generate_note_path(note.slug), params: {
        text: "Hello world",
        language: "en-US",
        voice: "af_heart",
        provider: "kokoro"
      }

      expect(response).to have_http_status(:accepted)
      json = response.parsed_body
      expect(json["cached"]).to be true
    end

    it "returns error for blank text" do
      post tts_generate_note_path(note.slug), params: {
        text: "",
        language: "en-US",
        voice: "af_heart",
        provider: "kokoro"
      }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /notes/:slug/tts_show" do
    it "returns active TTS asset info" do
      asset = create(:note_tts_asset, :with_audio, note_revision: revision)
      note.update!(head_revision_id: revision.id)

      get tts_show_note_path(note.slug)

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["id"]).to eq(asset.id)
      expect(json["ready"]).to be true
      expect(json["audio_url"]).to be_present
    end

    it "returns 404 when no active asset" do
      note.update!(head_revision_id: revision.id)

      get tts_show_note_path(note.slug)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /notes/:slug/tts_reject" do
    it "deactivates the TTS asset" do
      asset = create(:note_tts_asset, :with_audio, note_revision: revision)
      note.update!(head_revision_id: revision.id)

      patch tts_reject_note_path(note.slug), params: {tts_asset_id: asset.id}

      expect(response).to have_http_status(:ok)
      expect(asset.reload.is_active).to be false
    end

    it "returns 404 for missing asset" do
      note.update!(head_revision_id: revision.id)

      patch tts_reject_note_path(note.slug), params: {tts_asset_id: "missing"}

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /notes/:slug/tts_audio" do
    it "redirects to audio blob URL" do
      asset = create(:note_tts_asset, :with_audio, note_revision: revision)
      note.update!(head_revision_id: revision.id)

      get tts_audio_note_path(note.slug), params: {tts_asset_id: asset.id}

      expect(response).to have_http_status(:redirect)
    end

    it "returns 404 when no audio attached" do
      asset = create(:note_tts_asset, note_revision: revision)
      note.update!(head_revision_id: revision.id)

      get tts_audio_note_path(note.slug), params: {tts_asset_id: asset.id}

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /notes/:slug/tts_library" do
    it "returns all TTS assets for the note ordered by newest" do
      asset1 = create(:note_tts_asset, :with_audio, note_revision: revision, voice: "voice_a", created_at: 2.hours.ago)
      asset2 = create(:note_tts_asset, :with_audio, note_revision: revision, voice: "voice_b", created_at: 1.hour.ago)

      get tts_library_note_path(note.slug)

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["assets"].length).to eq(2)
      expect(json["assets"][0]["id"]).to eq(asset2.id)
      expect(json["assets"][1]["id"]).to eq(asset1.id)
    end

    it "includes assets from different revisions" do
      rev2 = create(:note_revision, note: note)
      create(:note_tts_asset, :with_audio, note_revision: revision)
      create(:note_tts_asset, :with_audio, note_revision: rev2)

      get tts_library_note_path(note.slug)

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["assets"].length).to eq(2)
    end

    it "does not include assets from other notes" do
      other_note = create(:note)
      other_rev = create(:note_revision, note: other_note)
      create(:note_tts_asset, :with_audio, note_revision: revision)
      create(:note_tts_asset, :with_audio, note_revision: other_rev)

      get tts_library_note_path(note.slug)

      json = response.parsed_body
      expect(json["assets"].length).to eq(1)
    end
  end

  context "when not authenticated" do
    before { sign_out user }

    it "redirects to login" do
      get tts_status_note_path(note.slug)
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
