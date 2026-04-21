require "rails_helper"

RSpec.describe Tentacles::CronTickJob, type: :job do
  before do
    PropertyDefinition.find_or_create_by!(key: "cron_expr") do |d|
      d.value_type = "text"
      d.system = true
    end
    PropertyDefinition.find_or_create_by!(key: "tentacle_cwd") do |d|
      d.value_type = "text"
      d.system = true
    end
    TentacleRuntime::SESSIONS.clear
    allow(WorktreeService).to receive(:ensure) do |tentacle_id:, repo_root: Rails.root|
      WorktreeService.path_for(tentacle_id: tentacle_id, repo_root: repo_root)
    end
  end

  after { TentacleRuntime::SESSIONS.clear }

  def make_cron_note(expr:, last_fired_at: nil, cwd: nil, body: "charter body")
    note = create(:note, title: "Cron test #{SecureRandom.hex(4)}")
    rev = create(:note_revision, note: note, content_markdown: body)
    note.update_columns(head_revision_id: rev.id)
    note.tags << Tag.find_or_create_by!(name: "cron")
    changes = {"cron_expr" => expr}
    changes["tentacle_cwd"] = cwd if cwd
    Properties::SetService.call(note: note, changes: changes)
    TentacleCronState.create!(note_id: note.id, last_fired_at: last_fired_at) if last_fired_at
    note.reload
  end

  describe "#perform" do
    it "does nothing when no note carries the cron tag" do
      expect(TentacleRuntime).not_to receive(:start)
      described_class.perform_now
    end

    it "is a no-op when Tentacles::Authorization.enabled? is false" do
      make_cron_note(expr: "* * * * *")
      allow(Tentacles::Authorization).to receive(:enabled?).and_return(false)

      expect(TentacleRuntime).not_to receive(:start)
      expect { described_class.perform_now }.not_to change { TentacleCronState.count }
    end

    it "fires a cron that has never run and whose cron_expr has a previous_time before now" do
      note = make_cron_note(expr: "* * * * *")
      fake = instance_double(TentacleRuntime::Session, alive?: true, pid: 1, started_at: Time.current)
      expect(TentacleRuntime).to receive(:start).with(
        hash_including(tentacle_id: note.id, command: %w[claude], initial_prompt: "charter body")
      ).and_return(fake)

      described_class.perform_now

      state = TentacleCronState.find_by(note_id: note.id)
      expect(state).not_to be_nil
      expect(state.last_attempted_at).to be_within(5.seconds).of(Time.current)
      expect(state.last_fired_at).to be_nil
    end

    it "does not fire when last_fired_at is newer than the most recent scheduled time" do
      note = make_cron_note(expr: "0 9 * * *", last_fired_at: Time.current)
      _ = note
      expect(TentacleRuntime).not_to receive(:start)

      described_class.perform_now
    end

    it "fires when last_fired_at is older than the most recent scheduled time" do
      travel_to Time.zone.local(2026, 4, 21, 9, 5, 0) do
        note = make_cron_note(expr: "0 9 * * *", last_fired_at: Time.zone.local(2026, 4, 20, 12, 0, 0))
        fake = instance_double(TentacleRuntime::Session, alive?: true, pid: 1, started_at: Time.current)
        expect(TentacleRuntime).to receive(:start).with(
          hash_including(tentacle_id: note.id)
        ).and_return(fake)

        described_class.perform_now
      end
    end

    it "skips a cron note whose cron_expr is invalid and logs a warning" do
      note = make_cron_note(expr: "not a cron")
      expect(TentacleRuntime).not_to receive(:start)
      expect(Rails.logger).to receive(:warn).with(/#{note.id}.*cron_expr/)

      described_class.perform_now
    end

    it "skips a cron note missing cron_expr property" do
      note = create(:note, title: "No expr")
      rev = create(:note_revision, note: note, content_markdown: "body")
      note.update_columns(head_revision_id: rev.id)
      note.tags << Tag.find_or_create_by!(name: "cron")

      expect(TentacleRuntime).not_to receive(:start)
      described_class.perform_now
    end

    it "does not fire again when a tentacle session is already alive for the note" do
      note = make_cron_note(expr: "* * * * *")
      existing = instance_double(TentacleRuntime::Session, alive?: true, pid: 4242, started_at: 1.minute.ago)
      TentacleRuntime::SESSIONS[note.id] = existing

      expect(TentacleRuntime).not_to receive(:start)
      described_class.perform_now
    end

    it "provisions an isolated worktree and passes it to TentacleRuntime.start as cwd" do
      note = make_cron_note(expr: "* * * * *", cwd: "/home/venom/projects/NeuraMD")
      fake = instance_double(TentacleRuntime::Session, alive?: true, pid: 1, started_at: Time.current)
      expected_path = WorktreeService.path_for(tentacle_id: note.id, repo_root: "/home/venom/projects/NeuraMD")

      expect(WorktreeService).to receive(:ensure).with(
        tentacle_id: note.id,
        repo_root: Pathname.new("/home/venom/projects/NeuraMD")
      ).and_return(expected_path)
      expect(TentacleRuntime).to receive(:start) do |**kwargs|
        expect(kwargs[:tentacle_id]).to eq(note.id)
        expect(kwargs[:cwd]).to eq(expected_path)
        fake
      end

      described_class.perform_now
    end

    it "falls back to Rails.root when tentacle_cwd is absent" do
      note = make_cron_note(expr: "* * * * *")
      fake = instance_double(TentacleRuntime::Session, alive?: true, pid: 1, started_at: Time.current)

      expect(WorktreeService).to receive(:ensure).with(
        tentacle_id: note.id,
        repo_root: Rails.root
      ).and_call_original
      allow(TentacleRuntime).to receive(:start).and_return(fake)

      described_class.perform_now
    end

    it "registers an on_exit callback that enqueues a CronLeaseReleaseJob with the run payload" do
      note = make_cron_note(expr: "* * * * *")
      fake = instance_double(TentacleRuntime::Session, alive?: true, pid: 1, started_at: Time.current)
      captured_on_exit = nil
      allow(TentacleRuntime).to receive(:start) do |**kwargs|
        captured_on_exit = kwargs[:on_exit]
        fake
      end

      described_class.perform_now

      claimed_token = TentacleCronState.find_by(note_id: note.id).lease_token
      expect(captured_on_exit).to respond_to(:call)

      started = 1.minute.ago
      ended = Time.current
      expect {
        captured_on_exit.call(
          transcript: "hello\n",
          command: %w[claude],
          started_at: started,
          ended_at: ended,
          exit_status: 0
        )
      }.to have_enqueued_job(Tentacles::CronLeaseReleaseJob).with(
        hash_including(
          note_id: note.id,
          lease_token: claimed_token,
          transcript: "hello\n",
          command: %w[claude],
          exit_status: 0
        )
      )
    end

    it "clears the lease inline when release-job enqueue raises so next tick can re-claim immediately" do
      note = make_cron_note(expr: "* * * * *")
      fake = instance_double(TentacleRuntime::Session, alive?: true, pid: 1, started_at: Time.current)
      captured_on_exit = nil
      allow(TentacleRuntime).to receive(:start) do |**kwargs|
        captured_on_exit = kwargs[:on_exit]
        fake
      end

      described_class.perform_now

      allow(Tentacles::CronLeaseReleaseJob).to receive(:perform_later)
        .and_raise(ActiveJob::SerializationError.new("queue db unreachable"))
      allow(Rails.logger).to receive(:error)

      expect do
        captured_on_exit.call(
          transcript: "hello\n",
          command: %w[claude],
          started_at: 1.minute.ago,
          ended_at: Time.current,
          exit_status: 0
        )
      end.not_to raise_error

      state = TentacleCronState.find_by(note_id: note.id)
      expect(state.last_attempted_at).to be_nil
      expect(state.lease_pid).to be_nil
      expect(state.lease_host).to be_nil
      expect(state.lease_token).to be_nil
      expect(state.last_fired_at).to be_nil
    end

    it "swallows and logs when both enqueue and inline lease clear fail" do
      note = make_cron_note(expr: "* * * * *")
      fake = instance_double(TentacleRuntime::Session, alive?: true, pid: 1, started_at: Time.current)
      captured_on_exit = nil
      allow(TentacleRuntime).to receive(:start) do |**kwargs|
        captured_on_exit = kwargs[:on_exit]
        fake
      end

      described_class.perform_now

      claimed_token = TentacleCronState.find_by(note_id: note.id).lease_token
      allow(Tentacles::CronLeaseReleaseJob).to receive(:perform_later)
        .and_raise(ActiveJob::SerializationError.new("queue db unreachable"))
      allow(TentacleCronState).to receive(:where)
        .with(note_id: note.id, lease_token: claimed_token)
        .and_raise(ActiveRecord::StatementInvalid.new("main db unreachable"))
      expect(Rails.logger).to receive(:error).at_least(:twice)

      expect do
        captured_on_exit.call(
          transcript: "hello\n",
          command: %w[claude],
          started_at: 1.minute.ago,
          ended_at: Time.current,
          exit_status: 0
        )
      end.not_to raise_error
    end

    it "claims the lease via last_attempted_at before start and the on_exit callback commits last_fired_at" do
      note = make_cron_note(expr: "* * * * *")
      fake = instance_double(TentacleRuntime::Session, alive?: true, pid: 1, started_at: Time.current)
      captured_on_exit = nil

      observed_attempt = nil
      observed_fire = nil
      allow(TentacleRuntime).to receive(:start) do |**kwargs|
        snapshot = TentacleCronState.find_by(note_id: note.id)
        observed_attempt = snapshot&.last_attempted_at
        observed_fire = snapshot&.last_fired_at
        captured_on_exit = kwargs[:on_exit]
        fake
      end

      described_class.perform_now

      expect(observed_attempt).not_to be_nil
      expect(observed_fire).to be_nil

      mid_run = TentacleCronState.find_by(note_id: note.id)
      expect(mid_run.last_attempted_at).not_to be_nil
      expect(mid_run.last_fired_at).to be_nil

      allow(Tentacles::TranscriptService).to receive(:persist)
      perform_enqueued_jobs do
        captured_on_exit.call(
          transcript: "done\n",
          command: %w[claude],
          started_at: 1.minute.ago,
          ended_at: Time.current,
          exit_status: 0
        )
      end

      final = TentacleCronState.find_by(note_id: note.id)
      expect(final.last_attempted_at).to be_nil
      expect(final.last_fired_at).to be_within(5.seconds).of(Time.current)
    end

    it "clears last_attempted_at when start raises so next tick retries" do
      note = make_cron_note(expr: "0 9 * * *")
      allow(TentacleRuntime).to receive(:start).and_raise("boot failed")
      allow(Rails.logger).to receive(:error)

      travel_to Time.zone.local(2026, 4, 21, 9, 5, 0) do
        described_class.perform_now
      end

      state = TentacleCronState.find_by(note_id: note.id)
      expect(state.last_fired_at).to be_nil
      expect(state.last_attempted_at).to be_nil

      fake = instance_double(TentacleRuntime::Session, alive?: true, pid: 1, started_at: Time.current)
      expect(TentacleRuntime).to receive(:start).and_return(fake)

      travel_to Time.zone.local(2026, 4, 21, 9, 6, 0) do
        described_class.perform_now
      end

      expect(state.reload.last_attempted_at).not_to be_nil
    end

    it "releases the lease but does not advance last_fired_at when transcript persistence raises" do
      note = make_cron_note(expr: "* * * * *")
      fake = instance_double(TentacleRuntime::Session, alive?: true, pid: 1, started_at: Time.current)
      captured_on_exit = nil
      allow(TentacleRuntime).to receive(:start) do |**kwargs|
        captured_on_exit = kwargs[:on_exit]
        fake
      end

      described_class.perform_now

      allow(Tentacles::TranscriptService).to receive(:persist).and_raise("disk full")
      allow(Rails.logger).to receive(:error)
      allow(Rails.logger).to receive(:warn)
      perform_enqueued_jobs do
        captured_on_exit.call(
          transcript: "x\n",
          command: %w[claude],
          started_at: 1.minute.ago,
          ended_at: Time.current,
          exit_status: 0
        )
      end

      final = TentacleCronState.find_by(note_id: note.id)
      expect(final.last_attempted_at).to be_nil
      expect(final.lease_pid).to be_nil
      expect(final.lease_host).to be_nil
      expect(final.last_fired_at).to be_nil
    end

    it "does not advance last_fired_at when the child exited non-zero" do
      note = make_cron_note(expr: "* * * * *")
      fake = instance_double(TentacleRuntime::Session, alive?: true, pid: 1, started_at: Time.current)
      captured_on_exit = nil
      allow(TentacleRuntime).to receive(:start) do |**kwargs|
        captured_on_exit = kwargs[:on_exit]
        fake
      end

      described_class.perform_now

      allow(Tentacles::TranscriptService).to receive(:persist)
      allow(Rails.logger).to receive(:warn)
      perform_enqueued_jobs do
        captured_on_exit.call(
          transcript: "oops\n",
          command: %w[claude],
          started_at: 1.minute.ago,
          ended_at: Time.current,
          exit_status: 1
        )
      end

      final = TentacleCronState.find_by(note_id: note.id)
      expect(final.last_fired_at).to be_nil
      expect(final.last_attempted_at).to be_nil
    end

    it "does not advance last_fired_at when exit_status is nil (unclean reap)" do
      note = make_cron_note(expr: "* * * * *")
      fake = instance_double(TentacleRuntime::Session, alive?: true, pid: 1, started_at: Time.current)
      captured_on_exit = nil
      allow(TentacleRuntime).to receive(:start) do |**kwargs|
        captured_on_exit = kwargs[:on_exit]
        fake
      end

      described_class.perform_now

      allow(Tentacles::TranscriptService).to receive(:persist)
      allow(Rails.logger).to receive(:warn)
      perform_enqueued_jobs do
        captured_on_exit.call(
          transcript: "partial\n",
          command: %w[claude],
          started_at: 1.minute.ago,
          ended_at: Time.current,
          exit_status: nil
        )
      end

      final = TentacleCronState.find_by(note_id: note.id)
      expect(final.last_fired_at).to be_nil
      expect(final.last_attempted_at).to be_nil
    end

    it "does not clobber a newer claim's lease when an old on_exit fires late" do
      note = make_cron_note(expr: "* * * * *")
      fake = instance_double(TentacleRuntime::Session, alive?: true, pid: 1, started_at: Time.current)
      captured_on_exit = nil
      allow(TentacleRuntime).to receive(:start) do |**kwargs|
        captured_on_exit = kwargs[:on_exit]
        fake
      end

      described_class.perform_now

      TentacleCronState.where(note_id: note.id).update_all(
        lease_pid: 999_999,
        lease_host: "different-host",
        lease_token: SecureRandom.uuid,
        last_attempted_at: Time.current
      )

      allow(Tentacles::TranscriptService).to receive(:persist)
      perform_enqueued_jobs do
        captured_on_exit.call(
          transcript: "done\n",
          command: %w[claude],
          started_at: 1.minute.ago,
          ended_at: Time.current,
          exit_status: 0
        )
      end

      final = TentacleCronState.find_by(note_id: note.id)
      expect(final.lease_pid).to eq(999_999)
      expect(final.lease_host).to eq("different-host")
      expect(final.last_fired_at).to be_nil
    end

    it "does not clobber a same-host reclaim that reuses this worker's pid" do
      note = make_cron_note(expr: "* * * * *")
      fake = instance_double(TentacleRuntime::Session, alive?: true, pid: 1, started_at: Time.current)
      captured_on_exit = nil
      allow(TentacleRuntime).to receive(:start) do |**kwargs|
        captured_on_exit = kwargs[:on_exit]
        fake
      end

      described_class.perform_now

      new_token = SecureRandom.uuid
      TentacleCronState.where(note_id: note.id).update_all(
        lease_token: new_token,
        last_attempted_at: Time.current
      )

      allow(Tentacles::TranscriptService).to receive(:persist)
      perform_enqueued_jobs do
        captured_on_exit.call(
          transcript: "done\n",
          command: %w[claude],
          started_at: 1.minute.ago,
          ended_at: Time.current,
          exit_status: 0
        )
      end

      final = TentacleCronState.find_by(note_id: note.id)
      expect(final.lease_token).to eq(new_token)
      expect(final.last_attempted_at).not_to be_nil
      expect(final.last_fired_at).to be_nil
    end

    it "records a unique lease_token when claiming a fresh lease" do
      note = make_cron_note(expr: "* * * * *")
      fake = instance_double(TentacleRuntime::Session, alive?: true, pid: 1, started_at: Time.current)
      allow(TentacleRuntime).to receive(:start).and_return(fake)

      described_class.perform_now

      state = TentacleCronState.find_by(note_id: note.id)
      expect(state.lease_token).to be_present
      expect(state.lease_token.length).to be >= 32
    end

    it "retries on the next tick after a failed run (lease cleared, not fired)" do
      travel_to Time.zone.local(2026, 4, 21, 9, 5, 0) do
        note = make_cron_note(expr: "0 9 * * *")
        first_on_exit = nil
        fake1 = instance_double(TentacleRuntime::Session, alive?: true, pid: 1, started_at: Time.current)
        allow(TentacleRuntime).to receive(:start) do |**kwargs|
          first_on_exit = kwargs[:on_exit]
          fake1
        end

        described_class.perform_now

        allow(Tentacles::TranscriptService).to receive(:persist)
        allow(Rails.logger).to receive(:warn)
        perform_enqueued_jobs do
          first_on_exit.call(
            transcript: "failed\n",
            command: %w[claude],
            started_at: Time.current,
            ended_at: Time.current,
            exit_status: 2
          )
        end

        fake2 = instance_double(TentacleRuntime::Session, alive?: true, pid: 2, started_at: Time.current)
        expect(TentacleRuntime).to receive(:start).and_return(fake2)

        described_class.perform_now

        state = TentacleCronState.find_by(note_id: note.id)
        expect(state.last_attempted_at).not_to be_nil
        expect(state.last_fired_at).to be_nil
      end
    end

    it "reclaims a stale lease older than STALE_LEASE_TTL" do
      travel_to Time.zone.local(2026, 4, 21, 12, 0, 0) do
        note = make_cron_note(expr: "0 9 * * *")
        TentacleCronState.create!(
          note_id: note.id,
          last_attempted_at: 3.hours.ago
        )
        fake = instance_double(TentacleRuntime::Session, alive?: true, pid: 1, started_at: Time.current)
        allow(Rails.logger).to receive(:warn)

        expect(Rails.logger).to receive(:warn).with(/reclaiming stale lease for note #{note.id}/)
        expect(TentacleRuntime).to receive(:start).and_return(fake)

        described_class.perform_now
      end
    end

    it "does not re-claim a lease held by a live in-flight run" do
      travel_to Time.zone.local(2026, 4, 21, 9, 5, 0) do
        note = make_cron_note(expr: "0 9 * * *")
        TentacleCronState.create!(
          note_id: note.id,
          last_attempted_at: Time.current - 30.seconds
        )
        live = instance_double(TentacleRuntime::Session, alive?: true, pid: 4242, started_at: 1.minute.ago)
        TentacleRuntime::SESSIONS[note.id] = live

        expect(TentacleRuntime).not_to receive(:start)
        described_class.perform_now
      end
    end

    it "reclaims a fresh lease when lease_pid is dead on the same host (process crash)" do
      travel_to Time.zone.local(2026, 4, 21, 9, 5, 0) do
        note = make_cron_note(expr: "0 9 * * *")
        dead_pid = 999_999
        TentacleCronState.create!(
          note_id: note.id,
          last_attempted_at: Time.current - 30.seconds,
          lease_pid: dead_pid,
          lease_host: Socket.gethostname
        )
        allow(Process).to receive(:kill).with(0, dead_pid).and_raise(Errno::ESRCH)
        fake = instance_double(TentacleRuntime::Session, alive?: true, pid: 1, started_at: Time.current)
        allow(Rails.logger).to receive(:warn)

        expect(Rails.logger).to receive(:warn).with(/orphaned lease.*#{note.id}.*pid #{dead_pid} dead/)
        expect(TentacleRuntime).to receive(:start).and_return(fake)

        described_class.perform_now

        state = TentacleCronState.find_by(note_id: note.id)
        expect(state.last_attempted_at).to be_within(5.seconds).of(Time.current)
        expect(state.lease_pid).to eq(Process.pid)
        expect(state.lease_host).to eq(Socket.gethostname)
      end
    end

    it "does not reclaim a fresh lease when lease_pid is still alive on the same host" do
      travel_to Time.zone.local(2026, 4, 21, 9, 5, 0) do
        note = make_cron_note(expr: "0 9 * * *")
        live_pid = 123_456
        TentacleCronState.create!(
          note_id: note.id,
          last_attempted_at: Time.current - 30.seconds,
          lease_pid: live_pid,
          lease_host: Socket.gethostname
        )
        allow(Process).to receive(:kill).with(0, live_pid).and_return(1)

        expect(TentacleRuntime).not_to receive(:start)
        described_class.perform_now
      end
    end

    it "respects TTL when the fresh lease was recorded on a different host" do
      travel_to Time.zone.local(2026, 4, 21, 9, 5, 0) do
        note = make_cron_note(expr: "0 9 * * *")
        TentacleCronState.create!(
          note_id: note.id,
          last_attempted_at: Time.current - 30.seconds,
          lease_pid: 12_345,
          lease_host: "other-host.example"
        )

        expect(Process).not_to receive(:kill)
        expect(TentacleRuntime).not_to receive(:start)
        described_class.perform_now
      end
    end

    it "respects TTL when the fresh lease has no recorded pid (legacy row)" do
      travel_to Time.zone.local(2026, 4, 21, 9, 5, 0) do
        note = make_cron_note(expr: "0 9 * * *")
        TentacleCronState.create!(
          note_id: note.id,
          last_attempted_at: Time.current - 30.seconds,
          lease_pid: nil,
          lease_host: nil
        )

        expect(Process).not_to receive(:kill)
        expect(TentacleRuntime).not_to receive(:start)
        described_class.perform_now
      end
    end

    it "records lease_pid and lease_host when claiming a fresh lease" do
      note = make_cron_note(expr: "* * * * *")
      fake = instance_double(TentacleRuntime::Session, alive?: true, pid: 1, started_at: Time.current)
      allow(TentacleRuntime).to receive(:start).and_return(fake)

      described_class.perform_now

      state = TentacleCronState.find_by(note_id: note.id)
      expect(state.lease_pid).to eq(Process.pid)
      expect(state.lease_host).to eq(Socket.gethostname)
    end

    it "catches errors from a single cron and continues processing others" do
      bad = make_cron_note(expr: "* * * * *", body: "bad charter")
      good = make_cron_note(expr: "* * * * *", body: "good charter")
      fake = instance_double(TentacleRuntime::Session, alive?: true, pid: 1, started_at: Time.current)

      allow(TentacleRuntime).to receive(:start) do |**kwargs|
        raise "boom" if kwargs[:tentacle_id] == bad.id
        fake
      end

      expect(Rails.logger).to receive(:error).with(/#{bad.id}/)
      expect { described_class.perform_now }.not_to raise_error
      expect(TentacleCronState.find_by(note_id: good.id)).not_to be_nil
    end
  end
end
