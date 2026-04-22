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

      workspace_name = props["tentacle_workspace"]
      workspace_path, workspace_err = Tentacles::Workspace.resolve(workspace_name)
      if workspace_err && workspace_name.present?
        Rails.logger.warn("Tentacles::CronTickJob note #{note.id} has invalid tentacle_workspace: #{workspace_err}")
        return
      end

      canonical_cwd = nil
      unless workspace_path
        canonical_cwd, cwd_err = Tentacles::BootConfig.canonicalize_cwd(props["tentacle_cwd"])
        if cwd_err
          Rails.logger.warn("Tentacles::CronTickJob note #{note.id} has invalid tentacle_cwd: #{cwd_err}")
          return
        end
      end

      body = note.head_revision&.content_markdown.to_s
      prompt, prompt_err = Tentacles::BootConfig.validate_initial_prompt(body)
      if prompt_err
        Rails.logger.warn("Tentacles::CronTickJob note #{note.id} initial_prompt rejected: #{prompt_err}")
        return
      end

      state = claim_lease(note: note, previous: previous, reclaim_orphan: reclaim_orphan)
      return unless state

      session = nil
      begin
        repo_root = workspace_path || canonical_cwd || Rails.root
        worktree_root = workspace_path ? Tentacles::Workspace.worktree_root_for(workspace_name) : nil
        link_shared = workspace_path.nil?

        worktree = WorktreeService.ensure(
          tentacle_id: note.id,
          repo_root: Pathname.new(repo_root),
          worktree_root: worktree_root,
          link_shared: link_shared
        )

        session = TentacleRuntime.start(
          tentacle_id: note.id,
          command: %w[claude],
          cwd: worktree,
          initial_prompt: prompt,
          persistence: {kind: "cron", lease_token: state.lease_token}
        )
      rescue StandardError
        state.update_columns(last_attempted_at: nil, lease_pid: nil, lease_host: nil, lease_token: nil)
        raise
      end

      transition_lease_to_child_pid(state: state, session: session)
    end

    def transition_lease_to_child_pid(state:, session:)
      child_pid = session&.pid
      return unless child_pid

      TentacleCronState
        .where(note_id: state.note_id, lease_token: state.lease_token)
        .update_all(lease_pid: child_pid)
    rescue StandardError => e
      Rails.logger.warn(
        "Tentacles::CronTickJob failed to transition lease_pid to child pid for note #{state.note_id}: " \
        "#{e.class}: #{e.message}; retaining worker pid (fast reclaim may wait for STALE_LEASE_TTL)"
      )
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
        lease_host: Socket.gethostname,
        lease_token: SecureRandom.uuid
      )
      return nil if rows.zero?

      TentacleCronState.find_by(note_id: note.id)
    end

    def ensure_state_row(note_id)
      TentacleCronState.create!(note_id: note_id)
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    public

    # Best-effort safety net when CronLeaseReleaseJob.perform_later raises
    # (queue DB unreachable, serialization error). Clears the lease inline
    # without advancing last_fired_at so the next tick can re-claim
    # immediately. Transcript is lost in this path — acceptable tradeoff
    # versus wedging the schedule for STALE_LEASE_TTL.
    # If the inline clear also fails, log and swallow; stale-TTL reclaim is
    # the ultimate backstop.
    def emergency_release_on_enqueue_failure(note_id:, lease_token:, error:)
      Rails.logger.error(
        "Tentacles::CronTickJob release-job enqueue failed for note #{note_id}: " \
        "#{error.class}: #{error.message}; clearing lease inline, transcript lost"
      )
      TentacleCronState
        .where(note_id: note_id, lease_token: lease_token)
        .update_all(last_attempted_at: nil, lease_pid: nil, lease_host: nil, lease_token: nil)
    rescue StandardError => e
      begin
        Rails.logger.error(
          "Tentacles::CronTickJob emergency lease clear failed for note #{note_id}: " \
          "#{e.class}: #{e.message}; falling back to STALE_LEASE_TTL reclaim"
        )
      rescue StandardError
        nil
      end
    end

    private
  end
end
