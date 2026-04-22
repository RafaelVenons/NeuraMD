require "rails_helper"

RSpec.describe TentacleSession, type: :model do
  subject(:session) { build(:tentacle_session) }

  describe "validations" do
    it "is valid with the factory defaults" do
      expect(session).to be_valid
    end

    it "requires a dtach_socket" do
      session.dtach_socket = nil
      expect(session).not_to be_valid
      expect(session.errors[:dtach_socket]).to be_present
    end

    it "requires a command" do
      session.command = nil
      expect(session).not_to be_valid
    end

    it "requires started_at" do
      session.started_at = nil
      expect(session).not_to be_valid
    end

    it "enforces status inclusion" do
      session.status = "not-a-real-status"
      expect(session).not_to be_valid
      expect(session.errors[:status]).to be_present
    end

    it "enforces exit_reason inclusion when present" do
      session.exit_reason = "unexpected"
      expect(session).not_to be_valid
    end

    it "allows exit_reason to be nil" do
      session.exit_reason = nil
      expect(session).to be_valid
    end

    it "uniqueness on dtach_socket is case-sensitive" do
      create(:tentacle_session, dtach_socket: "/run/nm-tentacles/abc.sock")
      dup = build(:tentacle_session, dtach_socket: "/run/nm-tentacles/abc.sock")
      expect(dup).not_to be_valid
      expect(dup.errors[:dtach_socket]).to be_present
    end
  end

  describe "scopes" do
    it ".alive returns only sessions with status=alive" do
      live = create(:tentacle_session)
      dead = create(:tentacle_session, :exited)
      expect(described_class.alive).to include(live)
      expect(described_class.alive).not_to include(dead)
    end

    it ".recently_ended returns ended sessions newest first" do
      older = create(:tentacle_session, :exited, ended_at: 2.hours.ago)
      newer = create(:tentacle_session, :exited, ended_at: 1.minute.ago)
      expect(described_class.recently_ended.to_a).to eq([newer, older])
    end

    it ".for_note scopes to a given tentacle_note_id" do
      note1 = create(:tentacle_session).note
      create(:tentacle_session, note: note1)
      other = create(:tentacle_session)
      expect(described_class.for_note(note1.id).pluck(:tentacle_note_id).uniq).to eq([note1.id])
      expect(described_class.for_note(note1.id)).not_to include(other)
    end
  end

  describe "state helpers" do
    let(:record) { create(:tentacle_session) }

    it "#alive? is true for status=alive only" do
      expect(record.alive?).to be true
      record.update!(status: "exited", ended_at: Time.current, exit_reason: "graceful")
      expect(record.alive?).to be false
    end

    it "#ended? covers exited and reaped" do
      record.update!(status: "exited", ended_at: Time.current, exit_reason: "graceful")
      expect(record.ended?).to be true
      record.update!(status: "reaped")
      expect(record.ended?).to be true
    end

    it "#mark_ended! stamps exit fields atomically" do
      record.mark_ended!(reason: "crash", exit_code: 137)
      record.reload
      expect(record.status).to eq("exited")
      expect(record.exit_reason).to eq("crash")
      expect(record.exit_code).to eq(137)
      expect(record.ended_at).to be_within(5.seconds).of(Time.current)
    end

    it "#mark_unknown! transitions to status=unknown and stamps last_seen_at" do
      record.mark_unknown!
      expect(record.reload.status).to eq("unknown")
      expect(record.last_seen_at).to be_within(5.seconds).of(Time.current)
    end
  end
end
