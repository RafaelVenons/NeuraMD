require "rails_helper"

RSpec.describe NoteTtsAsset, type: :model do
  describe "validations" do
    it "is valid with valid attributes" do
      asset = build(:note_tts_asset)
      expect(asset).to be_valid
    end

    it "requires language" do
      asset = build(:note_tts_asset, language: nil)
      expect(asset).not_to be_valid
      expect(asset.errors[:language]).to be_present
    end

    it "requires voice" do
      asset = build(:note_tts_asset, voice: nil)
      expect(asset).not_to be_valid
      expect(asset.errors[:voice]).to be_present
    end

    it "requires provider" do
      asset = build(:note_tts_asset, provider: nil)
      expect(asset).not_to be_valid
    end

    it "validates provider inclusion" do
      asset = build(:note_tts_asset, provider: "unknown")
      expect(asset).not_to be_valid
    end

    it "accepts all valid providers" do
      %w[elevenlabs fish_audio gemini kokoro].each do |p|
        asset = build(:note_tts_asset, provider: p)
        expect(asset).to be_valid, "expected provider '#{p}' to be valid"
      end
    end

    it "validates format inclusion" do
      asset = build(:note_tts_asset, format: "aac")
      expect(asset).not_to be_valid
    end

    it "requires text_sha256" do
      asset = build(:note_tts_asset, text_sha256: nil)
      expect(asset).not_to be_valid
    end

    it "requires settings_hash" do
      asset = build(:note_tts_asset, settings_hash: nil)
      expect(asset).not_to be_valid
    end
  end

  describe "scopes" do
    describe ".active" do
      it "returns only active assets" do
        active = create(:note_tts_asset, is_active: true)
        create(:note_tts_asset, is_active: false)
        expect(described_class.active).to eq([active])
      end
    end

    describe ".inactive" do
      it "returns only inactive assets" do
        create(:note_tts_asset, is_active: true)
        inactive = create(:note_tts_asset, is_active: false)
        expect(described_class.inactive).to eq([inactive])
      end
    end

    describe ".ready" do
      it "returns active assets with audio attached" do
        ready = create(:note_tts_asset, :with_audio)
        create(:note_tts_asset) # pending — no audio
        create(:note_tts_asset, :with_audio, :inactive) # has audio but inactive
        expect(described_class.ready).to eq([ready])
      end
    end

    describe ".pending" do
      it "returns active assets without audio attached" do
        pending_asset = create(:note_tts_asset) # no audio
        create(:note_tts_asset, :with_audio) # ready — has audio
        create(:note_tts_asset, :inactive) # inactive
        expect(described_class.pending).to eq([pending_asset])
      end
    end
  end

  describe ".find_cached" do
    it "returns active asset matching all cache key fields" do
      asset = create(:note_tts_asset,
        text_sha256: "abc123", language: "pt-BR", voice: "pf_dora",
        provider: "kokoro", model: nil, settings_hash: "def456")

      found = described_class.find_cached(
        text_sha256: "abc123", language: "pt-BR", voice: "pf_dora",
        provider: "kokoro", model: nil, settings_hash: "def456")

      expect(found).to eq(asset)
    end

    it "returns nil for inactive assets" do
      create(:note_tts_asset, :inactive,
        text_sha256: "abc123", language: "pt-BR", voice: "pf_dora",
        provider: "kokoro", model: nil, settings_hash: "def456")

      found = described_class.find_cached(
        text_sha256: "abc123", language: "pt-BR", voice: "pf_dora",
        provider: "kokoro", model: nil, settings_hash: "def456")

      expect(found).to be_nil
    end

    it "returns nil when no match" do
      found = described_class.find_cached(
        text_sha256: "missing", language: "en", voice: "v1",
        provider: "kokoro", model: nil, settings_hash: "x")
      expect(found).to be_nil
    end
  end

  describe "#deactivate!" do
    it "sets is_active to false" do
      asset = create(:note_tts_asset, is_active: true)
      asset.deactivate!
      expect(asset.reload.is_active).to be false
    end
  end

  describe "#ready?" do
    it "returns true when audio is attached" do
      asset = create(:note_tts_asset, :with_audio)
      expect(asset.ready?).to be true
    end

    it "returns false when no audio attached" do
      asset = create(:note_tts_asset)
      expect(asset.ready?).to be false
    end
  end

  describe "#pending?" do
    it "returns true when active and no audio" do
      asset = create(:note_tts_asset)
      expect(asset.pending?).to be true
    end

    it "returns false when audio is attached" do
      asset = create(:note_tts_asset, :with_audio)
      expect(asset.pending?).to be false
    end

    it "returns false when inactive" do
      asset = create(:note_tts_asset, :inactive)
      expect(asset.pending?).to be false
    end
  end

  describe "#alignment_ready?" do
    it "returns true when status is succeeded and data is present" do
      asset = create(:note_tts_asset,
        alignment_status: "succeeded",
        alignment_data: {"words" => [{"word" => "hello", "start" => 0.0, "end" => 0.5}], "duration_s" => 0.5})
      expect(asset.alignment_ready?).to be true
    end

    it "returns false when status is pending" do
      asset = create(:note_tts_asset, alignment_status: "pending")
      expect(asset.alignment_ready?).to be false
    end

    it "returns false when status is nil" do
      asset = create(:note_tts_asset, alignment_status: nil)
      expect(asset.alignment_ready?).to be false
    end

    it "returns false when status is succeeded but data is nil" do
      asset = create(:note_tts_asset, alignment_status: "succeeded", alignment_data: nil)
      expect(asset.alignment_ready?).to be false
    end
  end

  describe "#alignment_failed?" do
    it "returns true when status is failed" do
      asset = create(:note_tts_asset, alignment_status: "failed")
      expect(asset.alignment_failed?).to be true
    end
  end

  describe ".for_note" do
    it "returns assets across all revisions of the note" do
      note = create(:note, :with_head_revision)
      rev2 = create(:note_revision, note: note)
      asset1 = create(:note_tts_asset, note_revision: note.head_revision)
      asset2 = create(:note_tts_asset, note_revision: rev2)

      result = described_class.for_note(note)
      expect(result).to contain_exactly(asset1, asset2)
    end

    it "excludes assets from other notes" do
      note = create(:note, :with_head_revision)
      other_note = create(:note, :with_head_revision)
      create(:note_tts_asset, note_revision: note.head_revision)
      create(:note_tts_asset, note_revision: other_note.head_revision)

      result = described_class.for_note(note)
      expect(result.count).to eq(1)
    end
  end
end
