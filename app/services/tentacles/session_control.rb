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

    Result = Struct.new(:session, :reused, :command, :routed_prompt_delivered, keyword_init: true)

    def self.activate(note:, command:, initial_prompt: nil, persistence: {})
      new(note: note, command: command, initial_prompt: initial_prompt, persistence: persistence).activate
    end

    def initialize(note:, command:, initial_prompt:, persistence:)
      @note = note
      @command = command
      @initial_prompt = initial_prompt
      @persistence = persistence
    end

    def activate
      routed_prompt, err = ::Tentacles::BootConfig.validate_initial_prompt(@initial_prompt)
      raise InvalidBootConfig, err if err

      repo_root, worktree_root, link_shared, boot_prompt = sanitized_boot_config(@note)
      current_fingerprint = ::Tentacles::BootConfig.repo_root_fingerprint(repo_root)

      existing = ::TentacleRuntime.get(@note.id)
      if existing&.alive?
        assert_session_fresh!(existing, repo_root: repo_root, worktree_root: worktree_root, current_fingerprint: current_fingerprint)

        if routed_prompt.present?
          ::TentacleRuntime.write(tentacle_id: @note.id, data: "#{routed_prompt}\n")
        end
        return Result.new(
          session: existing,
          reused: true,
          command: @command,
          routed_prompt_delivered: routed_prompt.present?
        )
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
      Result.new(session: session, reused: false, command: @command, routed_prompt_delivered: delivered)
    end

    private

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
