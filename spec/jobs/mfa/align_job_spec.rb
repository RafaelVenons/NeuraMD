require "rails_helper"

RSpec.describe Mfa::AlignJob, type: :job do
  let(:note) { create(:note, :with_head_revision) }
  let(:asset) do
    a = create(:note_tts_asset, note_revision: note.head_revision, language: "en-US")
    a.audio.attach(io: StringIO.new("fake-audio"), filename: "test.mp3", content_type: "audio/mpeg")
    a
  end

  describe "#perform" do
    it "calls AlignService with the asset" do
      allow(Mfa::AlignService).to receive(:call)

      described_class.perform_now(asset.id)

      expect(Mfa::AlignService).to have_received(:call).with(asset)
    end

    it "sets alignment_status to pending before alignment" do
      allow(Mfa::AlignService).to receive(:call) do |a|
        expect(a.alignment_status).to eq("pending")
      end

      described_class.perform_now(asset.id)
    end

    it "skips if alignment already succeeded" do
      asset.update!(alignment_status: "succeeded")
      allow(Mfa::AlignService).to receive(:call)

      described_class.perform_now(asset.id)

      expect(Mfa::AlignService).not_to have_received(:call)
    end

    it "skips if audio is not attached" do
      asset.audio.purge
      allow(Mfa::AlignService).to receive(:call)

      described_class.perform_now(asset.id)

      expect(Mfa::AlignService).not_to have_received(:call)
    end

    it "marks asset as failed on permanent MFA error" do
      allow(Mfa::AlignService).to receive(:call).and_raise(Mfa::ExecutionError, "MFA crashed")

      described_class.perform_now(asset.id)

      expect(asset.reload.alignment_status).to eq("failed")
    end

    it "retries on TransientError" do
      allow(Mfa::AlignService).to receive(:call).and_raise(Mfa::TransientError, "SSH timeout")

      assert_enqueued_with(job: described_class) do
        described_class.perform_now(asset.id)
      end
    end

    it "enqueues on the mfa queue" do
      expect(described_class.new.queue_name).to eq("airch")
    end
  end
end
