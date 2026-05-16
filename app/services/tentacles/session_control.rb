module Tentacles
  # Extracts the tentacle session spawn/reuse flow from
  # Api::Tentacles::SessionsController#create so it can be called from
  # multiple entry points (web controller, S2S endpoint for Gerente,
  # future job). Single source of truth for boot-config validation,
  # staleness detection, worktree provisioning, and runtime start.
  class SessionControl
    class InvalidBootConfig < StandardError; end

    class StaleSession < StandardError
      attr_reader :reason, :current_cwd, :desired_cwd

      def initialize(reason:, current_cwd:, desired_cwd:)
        @reason = reason
        @current_cwd = current_cwd
        @desired_cwd = desired_cwd
        super("session boot config is stale (#{reason})")
      end
    end

    Result = Struct.new(:session, :reused, :command, :routed_prompt_delivered, :wake_coalesced, keyword_init: true)
    TerminateResult = Struct.new(:terminated, :pid, :escalated_to_kill, :ended_at, :reason, keyword_init: true)

    # Default grace window for the graceful TERM→KILL escalation in
    # SessionControl.terminate. Matches the historical default in
    # TentacleRuntime#stop (0.5s) but kept explicit here so the
    # symmetric activate/terminate surface has a single tunable.
    DEFAULT_TERMINATE_GRACE = 0.5

    # When activate is called with coalesce_wake (the auto-wake path),
    # a reused live session that was nudged within this window skips the
    # redundant submit_sequence write — it was just told to read its
    # inbox. Manual activations (coalesce_wake: false) are never
    # coalesced.
    WAKE_COALESCE_WINDOW = 8.seconds

    def self.activate(note:, command:, initial_prompt: nil, persistence: {}, coalesce_wake: false)
      new(
        note: note, command: command, initial_prompt: initial_prompt,
        persistence: persistence, coalesce_wake: coalesce_wake
      ).activate
    end

    # Symmetric counterpart to .activate. Stops the in-memory session
    # for `note` (if any) and returns a TerminateResult with the pid
    # that was running, whether stop escalated to SIGKILL, the
    # ended_at timestamp, and a reason when no session existed.
    #
    # Idempotent: callers can issue terminate without checking liveness
    # first. When SESSIONS has no entry for the note, returns
    # `terminated: false, reason: "no_session"` instead of raising.
    #
    # `force: true` passes grace: 0 to TentacleRuntime.stop so SIGKILL
    # is reached immediately after SIGTERM (vs. waiting the default
    # grace window). Use when a child is known stuck and graceful exit
    # is futile — e.g., a TUI deadlocked on a permission prompt.
    def self.terminate(note:, force: false)
      # get_or_reattach, not get: a dtach session owned by another web
      # process must still be stoppable from here — otherwise terminate
      # would report no_session while the child runs on elsewhere.
      existing = ::TentacleRuntime.get_or_reattach(note.id)
      unless existing
        return TerminateResult.new(
          terminated: false,
          pid: nil,
          escalated_to_kill: false,
          ended_at: Time.current,
          reason: "no_session"
        )
      end

      pid_before = existing.pid
      grace = force ? 0 : DEFAULT_TERMINATE_GRACE
      ::TentacleRuntime.stop(tentacle_id: note.id, grace: grace)

      escalated =
        begin
          existing.force_killed?
        rescue NoMethodError
          false
        end

      TerminateResult.new(
        terminated: true,
        pid: pid_before,
        escalated_to_kill: escalated,
        ended_at: Time.current,
        reason: nil
      )
    end

    def initialize(note:, command:, initial_prompt:, persistence:, coalesce_wake: false)
      @note = note
      @command = command
      @initial_prompt = initial_prompt
      @persistence = persistence
      @coalesce_wake = coalesce_wake
    end

    def activate
      routed_prompt, err = ::Tentacles::BootConfig.validate_initial_prompt(@initial_prompt)
      raise InvalidBootConfig, err if err

      repo_root, worktree_root, link_shared, boot_prompt = sanitized_boot_config(@note)
      current_fingerprint = ::Tentacles::BootConfig.repo_root_fingerprint(repo_root)

      # get_or_reattach, not get: when dtach is enabled, a session
      # spawned by another web process is reattached here through its
      # shared socket so it can be reused/nudged instead of triggering
      # a duplicate spawn.
      existing = ::TentacleRuntime.get_or_reattach(@note.id)
      if existing&.alive_for_reuse?
        assert_session_fresh!(existing, repo_root: repo_root, worktree_root: worktree_root, current_fingerprint: current_fingerprint)

        # Auto-wake coalescing: a live session nudged moments ago was
        # already told to read its inbox — a second submit_sequence
        # write is noise. Only applies when the caller opted in
        # (coalesce_wake); manual activations always deliver the prompt.
        if @coalesce_wake && routed_prompt.present? &&
            existing.recently_wake_nudged?(within: WAKE_COALESCE_WINDOW)
          return Result.new(
            session: existing,
            reused: true,
            command: @command,
            routed_prompt_delivered: false,
            wake_coalesced: true
          )
        end

        delivered =
          if routed_prompt.present?
            # The submit sequence depends on the command — claude sessions
            # need `\e[13u` (CSI Kitty keyboard Enter); other shells take
            # plain `\r`. Sending the wrong one leaves the prompt sitting
            # in the input field without ever being submitted. Existing
            # session knows its command, so delegate to it.
            #
            # The write can race a session that dies between
            # alive_for_reuse? and the write — Session#write returns
            # false in that case, and we must reflect that in
            # routed_prompt_delivered (and skip mark_wake_nudged!), or
            # the wake job would treat a dropped write as a real
            # delivery and strand the inbox message.
            written = ::TentacleRuntime.write(
              tentacle_id: @note.id,
              data: "#{routed_prompt}#{existing.submit_sequence}"
            )
            existing.mark_wake_nudged! if @coalesce_wake && written == true
            written == true
          else
            false
          end
        return Result.new(
          session: existing,
          reused: true,
          command: @command,
          routed_prompt_delivered: delivered,
          wake_coalesced: false
        )
      elsif existing
        # alive_for_reuse? said the SESSIONS entry is a zombie — child
        # PID looked alive (kill -0) but the channel is dead (writer
        # closed in dtach mode after attach proxy died, or PTY master
        # got EPIPE). Tear down the in-memory entry + DB record so the
        # fresh-spawn path below produces a clean session in one cycle
        # instead of the 4×-retry storm observed pre-fix on
        # post-`systemctl restart` wakes.
        invalidate_stale_session!(existing)
      end

      final_prompt = merge_prompts(boot_prompt, routed_prompt)
      cwd = WorktreeService.ensure(
        tentacle_id: @note.id,
        repo_root: repo_root,
        worktree_root: worktree_root,
        link_shared: link_shared
      )
      # YOLO opt-in: charters with property `tentacle_yolo=true` get
      # `defaultMode: bypassPermissions` written into the worktree's
      # Claude Code settings, so unattended agents (Sentinela de Deploy,
      # cron tentacles) don't deadlock at the first permission prompt.
      # Gerente/humans are expected to leave the property unset.
      WorktreeService.write_yolo_settings!(path: cwd) if yolo_enabled?(@note)
      session = ::TentacleRuntime.start(
        tentacle_id: @note.id,
        command: @command,
        cwd: cwd,
        initial_prompt: final_prompt,
        persistence: @persistence,
        repo_root_fingerprint: current_fingerprint,
        note_slug: @note.slug
      )
      delivered =
        if routed_prompt.present?
          session.respond_to?(:initial_prompt_delivered?) && session.initial_prompt_delivered?
        else
          false
        end
      # Only mark the session as recently wake-nudged when the spawn
      # CONFIRMED the prompt landed. If initial_prompt_delivered? is
      # false (PTY readiness race), marking would falsely coalesce a
      # follow-up message into a wake that never actually reached the
      # agent (Codex finding: failed delivery still treated as nudge).
      session.mark_wake_nudged! if @coalesce_wake && delivered && session.respond_to?(:mark_wake_nudged!)
      Result.new(
        session: session, reused: false, command: @command,
        routed_prompt_delivered: delivered, wake_coalesced: false
      )
    end

    private

    # Tear down a SESSIONS map entry that the alive_for_reuse? probe
    # rejected as a zombie (channel dead even though kill -0 still
    # claims the pid is up). Three steps, each idempotent so this is
    # safe under concurrent activate calls and against the reader
    # thread's own delete-on-EOF path:
    #
    #   1. Drop the in-memory map entry — Concurrent::Map.delete is
    #      thread-safe and a no-op if another path already removed it.
    #   2. Mark every still-alive TentacleSession DB record for this
    #      note as ended with reason "missing_pid" (closest existing
    #      EXIT_REASON to "shallow kill -0 lied"). Without this,
    #      `agent_status` would keep reporting alive_sessions:1
    #      pointing at the just-invalidated zombie.
    #   3. Best-effort cleanup of the dtach socket/pidfile so the next
    #      bootstrap_sessions! sweep does not pick the corpse back up.
    #
    # Errors at any step are swallowed (logged) — the caller is about
    # to fall through to fresh spawn, which is the recovery; raising
    # here would defeat the whole point of the invalidation.
    def invalidate_stale_session!(existing)
      ::TentacleRuntime::SESSIONS.delete(@note.id)

      ::TentacleSession.alive.where(tentacle_note_id: @note.id).find_each do |record|
        record.mark_ended!(reason: "missing_pid")
      rescue StandardError => e
        Rails.logger.warn(
          "[session_control] invalidate_stale_session! failed to finalize record " \
          "#{record.id} for tentacle #{@note.id}: #{e.class}: #{e.message}"
        )
      end

      cleanup_stale_dtach_artifacts(existing)
    rescue StandardError => e
      Rails.logger.warn(
        "[session_control] invalidate_stale_session! raised " \
        "#{e.class} for tentacle #{@note.id}: #{e.message}"
      )
    end

    def cleanup_stale_dtach_artifacts(existing)
      wrapper = existing.respond_to?(:dtach) ? existing.dtach : nil
      return unless wrapper
      wrapper.cleanup
    rescue StandardError
      # Best-effort: socket/pidfile removal is supervised by
      # SupervisorJob.cleanup_orphaned_sockets as a backstop.
    end

    # Guards session reuse: refuse to reuse a live session whose
    # worktree path or repo identity diverged from the current boot
    # config. Either divergence means the session is attached to a
    # stale target and routing input there would write to the wrong
    # repo.
    def assert_session_fresh!(existing, repo_root:, worktree_root:, current_fingerprint:)
      desired_cwd = WorktreeService.path_for(
        tentacle_id: @note.id,
        repo_root: repo_root,
        worktree_root: worktree_root
      )
      cwd_stale = existing.cwd && existing.cwd.to_s != desired_cwd.to_s
      repo_stale =
        existing.repo_root_fingerprint &&
        current_fingerprint &&
        existing.repo_root_fingerprint != current_fingerprint
      # Sessions whose fingerprint key was never persisted (records
      # that predate this guard's persistence wiring) are exempt from
      # the unrecoverable check on a one-time, log-loud basis: they
      # would otherwise strand every alive tentacle the moment the
      # patch lands. They will rotate naturally on the next stop and
      # come back with a real persisted fingerprint.
      pre_persistence = existing.pre_persistence_fingerprint?

      # Post-fix sessions that nevertheless reattached without a
      # fingerprint (key present in metadata but value nil) cannot be
      # verified — fail-closed instead of falling through to the silent
      # bypass shape PR #21's guard intended to prevent.
      fingerprint_unrecoverable =
        current_fingerprint &&
        existing.repo_root_fingerprint.nil? &&
        !pre_persistence

      if pre_persistence && current_fingerprint && existing.repo_root_fingerprint.nil?
        Rails.logger.warn(
          "[session_control] reusing legacy session for tentacle #{@note.id} without fingerprint verification " \
          "(record predates fingerprint persistence); will rotate on next stop"
        )
      end

      return unless cwd_stale || repo_stale || fingerprint_unrecoverable

      reason =
        if cwd_stale
          "cwd_changed"
        elsif repo_stale
          "repo_identity_changed"
        else
          "fingerprint_unrecoverable"
        end

      raise StaleSession.new(
        reason: reason,
        current_cwd: existing.cwd.to_s,
        desired_cwd: desired_cwd.to_s
      )
    end

    # Resolves boot config from note properties following the same
    # contract as SessionsController: tentacle_workspace wins over
    # tentacle_cwd, both fail closed when declared but unresolvable.
    def sanitized_boot_config(note)
      props = note.current_properties

      workspace_name = props["tentacle_workspace"]
      workspace_path = nil
      if workspace_name.present?
        workspace_path, workspace_err = ::Tentacles::Workspace.resolve(workspace_name)
        if workspace_err
          Rails.logger.warn("Tentacle #{note.id} tentacle_workspace rejected at session start: #{workspace_err}")
          raise InvalidBootConfig, "tentacle_workspace: #{workspace_err}"
        end
      end

      canonical_cwd = nil
      unless workspace_path
        canonical_cwd, cwd_err = ::Tentacles::BootConfig.canonicalize_cwd(props["tentacle_cwd"])
        if cwd_err && props["tentacle_cwd"].present?
          Rails.logger.warn("Tentacle #{note.id} tentacle_cwd rejected at session start: #{cwd_err}")
          raise InvalidBootConfig, "tentacle_cwd: #{cwd_err}"
        end
      end

      validated_prompt, prompt_err = ::Tentacles::BootConfig.validate_initial_prompt(props["tentacle_initial_prompt"])
      if prompt_err
        Rails.logger.warn("Tentacle #{note.id} tentacle_initial_prompt rejected at session start: #{prompt_err}")
      end

      repo_root = workspace_path || canonical_cwd || Rails.root
      worktree_root = workspace_path ? ::Tentacles::Workspace.worktree_root_for(workspace_name) : nil
      link_shared = workspace_path.nil?

      [repo_root, worktree_root, link_shared, validated_prompt]
    end

    def merge_prompts(boot, routed)
      return boot if routed.nil? || routed.empty?
      return routed if boot.nil? || boot.empty?
      "#{boot}\n\n#{routed}"
    end

    # Truthy check that accepts the boolean `true` stored by
    # Properties::SetService for typed boolean PDs as well as the
    # string fallbacks ("true"/"1") that earlier ad-hoc writes used
    # before tentacle_yolo had a system PropertyDefinition.
    def yolo_enabled?(note)
      raw = note.current_properties["tentacle_yolo"]
      return true if raw == true
      %w[true 1].include?(raw.to_s.strip.downcase)
    end
  end
end
