require "fugit"
require "socket"

module Tentacles
  class CronTickJob < ApplicationJob
    queue_as :default

    STALE_LEASE_TTL = 2.hours

    def perform
      return unless Tentacles::Authorization.enabled?

      cron_tag = Tag.find_by(name: "cron")
      return unless cron_tag

      cron_tag.notes.active.includes(:head_revision).find_each do |note|
        process_note(note)
      rescue StandardError => e
        Rails.logger.error("Tentacles::CronTickJob failed for note #{note.id}: #{e.class}: #{e.message}")
      end
    end

    private

    def process_note(note)
      props = note.current_properties
      expr = props["cron_expr"].to_s.strip
      return if expr.empty?

      cron = Fugit::Cron.parse(expr)
      unless cron
        Rails.logger.warn("Tentacles::CronTickJob note #{note.id} has invalid cron_expr: #{expr.inspect}")
        return
      end

      previous = cron.previous_time(Time.current).to_t
      existing_state = TentacleCronState.find_by(note_id: note.id)
      return if existing_state&.last_fired_at && existing_state.last_fired_at >= previous

      return if TentacleRuntime.get(note.id)&.alive?

      reclaim_orphan = false
      if existing_state&.last_attempted_at
        if existing_state.last_attempted_at > STALE_LEASE_TTL.ago
          if orphaned_by_dead_pid?(existing_state)
            Rails.logger.warn("Tentacles::CronTickJob reclaiming orphaned lease for note #{note.id} (pid #{existing_state.lease_pid} dead on #{existing_state.lease_host})")
            reclaim_orphan = true
          else
            return
          end
        else
          Rails.logger.warn("Tentacles::CronTickJob reclaiming stale lease for note #{note.id} (attempted at #{existing_state.last_attempted_at.iso8601})")
        end
      end

      canonical_cwd, cwd_err = Tentacles::BootConfig.canonicalize_cwd(props["tentacle_cwd"])
      if cwd_err
        Rails.logger.warn("Tentacles::CronTickJob note #{note.id} has invalid tentacle_cwd: #{cwd_err}")
        return
      end

      body = note.head_revision&.content_markdown.to_s
      prompt, prompt_err = Tentacles::BootConfig.validate_initial_prompt(body)
      if prompt_err
        Rails.logger.warn("Tentacles::CronTickJob note #{note.id} initial_prompt rejected: #{prompt_err}")
        return
      end

      state = claim_lease(note: note, previous: previous, reclaim_orphan: reclaim_orphan)
      return unless state

      begin
        repo_root = canonical_cwd ? Pathname.new(canonical_cwd) : Rails.root
        worktree = WorktreeService.ensure(tentacle_id: note.id, repo_root: repo_root)

        TentacleRuntime.start(
          tentacle_id: note.id,
          command: %w[claude],
          cwd: worktree,
          initial_prompt: prompt,
          on_exit: build_on_exit(note, lease_pid: state.lease_pid, lease_host: state.lease_host)
        )
      rescue StandardError
        state.update_columns(last_attempted_at: nil, lease_pid: nil, lease_host: nil)
        raise
      end
    end

    def orphaned_by_dead_pid?(state)
      return false unless state.lease_pid && state.lease_host
      return false unless state.lease_host == Socket.gethostname
      !process_alive?(state.lease_pid)
    end

    def process_alive?(pid)
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true
    end

    def claim_lease(note:, previous:, reclaim_orphan: false)
      ensure_state_row(note.id)
      query = TentacleCronState
        .where(note_id: note.id)
        .where("last_fired_at IS NULL OR last_fired_at < ?", previous)
      unless reclaim_orphan
        query = query.where("last_attempted_at IS NULL OR last_attempted_at < ?", STALE_LEASE_TTL.ago)
      end
      rows = query.update_all(
        last_attempted_at: Time.current,
        lease_pid: Process.pid,
        lease_host: Socket.gethostname
      )
      return nil if rows.zero?

      TentacleCronState.find_by(note_id: note.id)
    end

    def ensure_state_row(note_id)
      TentacleCronState.create!(note_id: note_id)
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    def build_on_exit(note, lease_pid:, lease_host:)
      ->(transcript:, command:, started_at:, ended_at:, exit_status: nil, **) do
        persisted = false
        begin
          Tentacles::TranscriptService.persist(
            note: note,
            transcript: transcript,
            command: command,
            started_at: started_at,
            ended_at: ended_at,
            author: nil
          )
          persisted = true
        rescue StandardError => e
          Rails.logger.error("Tentacles::CronTickJob transcript persistence failed for #{note.id}: #{e.class}: #{e.message}")
        ensure
          release_cron_lease(
            note_id: note.id,
            lease_pid: lease_pid,
            lease_host: lease_host,
            persisted: persisted,
            exit_status: exit_status
          )
        end
      end
    end

    def release_cron_lease(note_id:, lease_pid:, lease_host:, persisted:, exit_status:)
      success = persisted && exit_status == 0
      updates = { last_attempted_at: nil, lease_pid: nil, lease_host: nil }
      updates[:last_fired_at] = Time.current if success

      TentacleCronState
        .where(note_id: note_id, lease_pid: lease_pid, lease_host: lease_host)
        .update_all(updates)

      return if success
      Rails.logger.warn("Tentacles::CronTickJob cron run failed for note #{note_id} (exit_status=#{exit_status.inspect}, persisted=#{persisted}); retry on next tick")
    rescue StandardError => e
      begin
        Rails.logger.error("Tentacles::CronTickJob lease cleanup failed for note #{note_id}: #{e.class}: #{e.message}")
      rescue StandardError
        nil
      end
    end
  end
end
