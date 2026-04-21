require "rails_helper"

RSpec.describe Tentacles::CronLeaseReleaseJob, type: :job do
  let(:note) { create(:note, title: "Cron release target") }
  let(:token) { SecureRandom.uuid }
  let(:started_at) { 1.minute.ago }
  let(:ended_at) { Time.current }

  def default_args(overrides = {})
    {
      note_id: note.id,
      lease_token: token,
      transcript: "hello\n",
      command: %w[claude],
      started_at: started_at.iso8601(6),
      ended_at: ended_at.iso8601(6),
      exit_status: 0
    }.merge(overrides)
  end

  before do
    TentacleCronState.create!(
      note_id: note.id,
      last_attempted_at: 10.minutes.ago,
      lease_pid: 42_424,
      lease_host: "legacy-host",
      lease_token: token
    )
  end

  describe "#perform — successful run" do
    it "persists the transcript, clears the lease, and advances last_fired_at" do
      expect(Tentacles::TranscriptService).to receive(:persist).with(
        hash_including(note: note, transcript: "hello\n", command: %w[claude])
      )

      freeze_time do
        described_class.perform_now(**default_args)
        state = TentacleCronState.find_by(note_id: note.id)
        expect(state.last_attempted_at).to be_nil
        expect(state.lease_pid).to be_nil
        expect(state.lease_host).to be_nil
        expect(state.lease_token).to be_nil
        expect(state.last_fired_at).to be_within(1.second).of(Time.current)
      end
    end
  end

  describe "#perform — non-zero exit" do
    it "clears the lease without advancing last_fired_at" do
      allow(Tentacles::TranscriptService).to receive(:persist)
      described_class.perform_now(**default_args(exit_status: 2))

      state = TentacleCronState.find_by(note_id: note.id)
      expect(state.last_attempted_at).to be_nil
      expect(state.lease_pid).to be_nil
      expect(state.lease_host).to be_nil
      expect(state.lease_token).to be_nil
      expect(state.last_fired_at).to be_nil
    end
  end

  describe "#perform — non-DB transcript persist error with successful child" do
    it "advances last_fired_at and logs transcript loss (child side effects already happened; no re-run)" do
      allow(Tentacles::TranscriptService).to receive(:persist).and_raise("disk full")
      expect(Rails.logger).to receive(:error).with(/transcript persist failed/)
      expect(Rails.logger).to receive(:error).with(/advancing last_fired_at without transcript/)

      described_class.perform_now(**default_args)

      state = TentacleCronState.find_by(note_id: note.id)
      expect(state.last_attempted_at).to be_nil
      expect(state.lease_pid).to be_nil
      expect(state.lease_host).to be_nil
      expect(state.lease_token).to be_nil
      expect(state.last_fired_at).to be_within(5.seconds).of(Time.current)
    end
  end

  describe "#perform — DB transcript persist error" do
    it "re-enqueues via retry_on and leaves the lease intact so next attempt can commit" do
      allow(Tentacles::TranscriptService).to receive(:persist)
        .and_raise(ActiveRecord::StatementInvalid.new("conn lost"))

      expect {
        described_class.perform_now(**default_args)
      }.to have_enqueued_job(described_class)
        .with(hash_including(note_id: note.id, lease_token: token, exit_status: 0))

      state = TentacleCronState.find_by(note_id: note.id)
      expect(state.lease_token).to eq(token)
      expect(state.last_fired_at).to be_nil
    end
  end

  describe "#perform — identity-scoped cleanup" do
    it "is a no-op and logs a stale-release warning when the row has been re-claimed with a different lease_token" do
      other_token = SecureRandom.uuid
      TentacleCronState.where(note_id: note.id).update_all(
        lease_token: other_token,
        last_attempted_at: Time.current,
        lease_pid: 9_999_999,
        lease_host: "newer-host"
      )
      allow(Tentacles::TranscriptService).to receive(:persist)
      expect(Rails.logger).to receive(:warn).with(/stale release/)

      described_class.perform_now(**default_args)

      state = TentacleCronState.find_by(note_id: note.id)
      expect(state.lease_token).to eq(other_token)
      expect(state.last_attempted_at).not_to be_nil
      expect(state.last_fired_at).to be_nil
    end
  end

  describe "#perform — persist succeeds but update_all raises" do
    it "rolls back the transcript and re-enqueues via retry_on" do
      allow(Tentacles::TranscriptService).to receive(:persist) do
        note.note_revisions.create!(content_markdown: "canary", revision_kind: :checkpoint)
      end
      allow(TentacleCronState).to receive(:where)
        .with(note_id: note.id, lease_token: token)
        .and_raise(ActiveRecord::StatementInvalid.new("db unreachable"))

      expect {
        described_class.perform_now(**default_args)
      }.to have_enqueued_job(described_class)
        .with(hash_including(note_id: note.id, lease_token: token, exit_status: 0))

      expect(note.note_revisions.where(content_markdown: "canary")).to be_empty
    end
  end

  describe "#perform — missing note" do
    it "discards itself when the note has been deleted" do
      allow(Tentacles::TranscriptService).to receive(:persist)
      note.destroy!

      expect {
        described_class.perform_now(**default_args)
      }.not_to raise_error
    end
  end
end
