require "rails_helper"

RSpec.describe TentacleRuntime::Persistence do
  let(:note) { create(:note, title: "Persistence Note") }
  let(:tentacle_id) { note.id }

  describe ".validate!" do
    it "returns nil when descriptor is nil" do
      expect(described_class.validate!(nil)).to be_nil
    end

    it "normalizes string-keyed hashes" do
      result = described_class.validate!(kind: "web", author_id: 5)
      expect(result).to eq("kind" => "web", "author_id" => 5)
    end

    it "rejects an unknown kind" do
      expect { described_class.validate!(kind: "mystery") }
        .to raise_error(ArgumentError, /unknown persistence kind/)
    end

    it "rejects a blank kind" do
      expect { described_class.validate!(kind: "") }
        .to raise_error(ArgumentError, /persistence kind/)
    end
  end

  describe ".build_on_exit" do
    it "returns nil when descriptor is nil" do
      expect(described_class.build_on_exit(nil, tentacle_id: tentacle_id)).to be_nil
    end

    context "web kind" do
      let(:user) { create(:user) }
      let(:descriptor) { {"kind" => "web", "author_id" => user.id} }

      it "calls TranscriptService.persist with the note, transcript and resolved author" do
        expect(Tentacles::TranscriptService).to receive(:persist).with(
          note: note,
          transcript: "hello\n",
          command: %w[bash],
          started_at: kind_of(Time),
          ended_at: kind_of(Time),
          author: user
        )

        callback = described_class.build_on_exit(descriptor, tentacle_id: tentacle_id)
        callback.call(
          transcript: "hello\n",
          command: %w[bash],
          started_at: 2.minutes.ago,
          ended_at: Time.current,
          exit_status: 0
        )
      end

      it "passes author=nil when the user cannot be resolved" do
        expect(Tentacles::TranscriptService).to receive(:persist).with(hash_including(author: nil))

        callback = described_class.build_on_exit(
          {"kind" => "web", "author_id" => 0},
          tentacle_id: tentacle_id
        )
        callback.call(
          transcript: "x",
          command: %w[bash],
          started_at: Time.current,
          ended_at: Time.current,
          exit_status: 0
        )
      end

      it "is a no-op when the note has been deleted" do
        note.destroy
        expect(Tentacles::TranscriptService).not_to receive(:persist)

        callback = described_class.build_on_exit(descriptor, tentacle_id: tentacle_id)
        callback.call(
          transcript: "x",
          command: %w[bash],
          started_at: Time.current,
          ended_at: Time.current,
          exit_status: 0
        )
      end
    end

    context "cron kind" do
      let(:lease_token) { SecureRandom.uuid }
      let(:descriptor) { {"kind" => "cron", "lease_token" => lease_token} }

      it "enqueues CronLeaseReleaseJob with note_id, lease_token, and normalized timestamps" do
        callback = described_class.build_on_exit(descriptor, tentacle_id: tentacle_id)

        expect {
          callback.call(
            transcript: "hi\n",
            command: %w[claude],
            started_at: Time.utc(2026, 4, 22),
            ended_at: Time.utc(2026, 4, 22, 0, 1),
            exit_status: 0
          )
        }.to have_enqueued_job(Tentacles::CronLeaseReleaseJob).with(
          hash_including(
            note_id: tentacle_id,
            lease_token: lease_token,
            transcript: "hi\n",
            command: %w[claude],
            exit_status: 0
          )
        )
      end

      it "normalizes nil timestamps into current iso8601 strings" do
        callback = described_class.build_on_exit(descriptor, tentacle_id: tentacle_id)

        expect {
          callback.call(
            transcript: "hi\n",
            command: %w[claude],
            started_at: nil,
            ended_at: nil,
            exit_status: 0
          )
        }.to have_enqueued_job(Tentacles::CronLeaseReleaseJob).with(
          hash_including(
            started_at: a_string_matching(/\A\d{4}-\d{2}-\d{2}T/),
            ended_at: a_string_matching(/\A\d{4}-\d{2}-\d{2}T/)
          )
        )
      end

      it "falls back to emergency_release_on_enqueue_failure when perform_later raises" do
        allow(Tentacles::CronLeaseReleaseJob).to receive(:perform_later)
          .and_raise(ActiveJob::SerializationError.new("queue down"))
        fake_tick = instance_double(Tentacles::CronTickJob, emergency_release_on_enqueue_failure: nil)
        allow(Tentacles::CronTickJob).to receive(:new).and_return(fake_tick)

        callback = described_class.build_on_exit(descriptor, tentacle_id: tentacle_id)

        expect(fake_tick).to receive(:emergency_release_on_enqueue_failure).with(
          note_id: tentacle_id,
          lease_token: lease_token,
          error: instance_of(ActiveJob::SerializationError)
        )

        expect {
          callback.call(
            transcript: "x",
            command: %w[claude],
            started_at: Time.current,
            ended_at: Time.current,
            exit_status: 0
          )
        }.not_to raise_error
      end
    end
  end
end
