require "rails_helper"

RSpec.describe Tentacles::CronLeaseReleaseJob, type: :job do
  let(:note) { create(:note, title: "Cron release target") }
  let(:token) { SecureRandom.uuid }

  before do
    TentacleCronState.create!(
      note_id: note.id,
      last_attempted_at: 10.minutes.ago,
      lease_pid: 42_424,
      lease_host: "legacy-host",
      lease_token: token
    )
  end

  it "clears the lease identity and advances last_fired_at when success=true" do
    freeze_time do
      described_class.perform_now(note_id: note.id, lease_token: token, success: true)
      state = TentacleCronState.find_by(note_id: note.id)
      expect(state.last_attempted_at).to be_nil
      expect(state.lease_pid).to be_nil
      expect(state.lease_host).to be_nil
      expect(state.lease_token).to be_nil
      expect(state.last_fired_at).to be_within(1.second).of(Time.current)
    end
  end

  it "clears the lease identity without advancing last_fired_at when success=false" do
    described_class.perform_now(note_id: note.id, lease_token: token, success: false)
    state = TentacleCronState.find_by(note_id: note.id)
    expect(state.last_attempted_at).to be_nil
    expect(state.lease_pid).to be_nil
    expect(state.lease_host).to be_nil
    expect(state.lease_token).to be_nil
    expect(state.last_fired_at).to be_nil
  end

  it "is a no-op when lease_token no longer matches (already reclaimed)" do
    described_class.perform_now(note_id: note.id, lease_token: "stale-token", success: true)
    state = TentacleCronState.find_by(note_id: note.id)
    expect(state.lease_token).to eq(token)
    expect(state.last_fired_at).to be_nil
  end

  it "re-enqueues itself when update_all raises a StatementInvalid" do
    allow(TentacleCronState).to receive(:where)
      .with(note_id: note.id, lease_token: token)
      .and_raise(ActiveRecord::StatementInvalid.new("db unreachable"))

    expect {
      described_class.perform_now(note_id: note.id, lease_token: token, success: true)
    }.to have_enqueued_job(described_class)
      .with(hash_including(note_id: note.id, lease_token: token, success: true))
  end
end
