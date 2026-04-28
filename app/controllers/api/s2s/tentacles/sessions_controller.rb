module Api
  module S2s
    module Tentacles
      # Programmatic tentacle session control surface used by agents
      # (notably the Gerente) to activate other agents without the
      # human opening each one in the web UI. Auth via shared S2S
      # token — see Api::S2s::BaseController.
      #
      # Additional trust beyond the token: the target note must carry
      # a canonical agent tag (prefix `agente-`). Prevents the S2S
      # endpoint from activating arbitrary notes.
      class SessionsController < Api::S2s::BaseController
        KNOWN_COMMANDS = {
          "bash" => ["bash", "-l"],
          "claude" => ["claude"]
        }.freeze

        AGENT_TAG_PREFIX = "agente-".freeze

        before_action :set_note
        before_action :ensure_agent_note!

        def activate
          command = resolve_command(params[:command])

          result = ::Tentacles::SessionControl.activate(
            note: @note,
            command: command,
            initial_prompt: params[:initial_prompt],
            persistence: {kind: "s2s"}
          )

          status = result.reused ? :ok : :created
          render json: serialize(@note, result, command: command), status: status
        rescue ::Tentacles::SessionControl::InvalidBootConfig => e
          render json: {error: e.message}, status: :unprocessable_entity
        rescue ::Tentacles::SessionControl::StaleSession => e
          render json: {
            error: "session boot config is stale. DELETE /api/s2s/tentacles/#{@note.slug} then POST again.",
            stale_boot_config: true,
            stale_reason: e.reason,
            current_cwd: e.current_cwd,
            desired_cwd: e.desired_cwd
          }, status: :conflict
        rescue ::WorktreeService::DirtyWorktreeError => e
          render json: {
            error: "tentacle worktree has uncommitted local changes; refusing to refresh. " \
                   "commit, stash, or push the branch from the worktree, then retry.",
            dirty_worktree: true,
            detail: e.message
          }, status: :conflict
        end

        def destroy
          force = ActiveModel::Type::Boolean.new.cast(params[:force])
          result = ::Tentacles::SessionControl.terminate(note: @note, force: force)

          payload = {
            # `stopped` is the legacy field; preserved so existing
            # callers (web UI delete button, prior MCP integrations)
            # keep working. New callers should prefer `terminated`,
            # which distinguishes the no-session idempotent path.
            stopped: true,
            terminated: result.terminated,
            slug: @note.slug,
            tentacle_id: @note.id,
            pid: result.pid,
            escalated_to_kill: result.escalated_to_kill,
            ended_at: result.ended_at&.utc&.iso8601
          }
          payload[:reason] = result.reason if result.reason

          render json: payload
        end

        private

        def set_note
          @note = Note.active.find_by(slug: params[:slug])
          render_not_found unless @note
        end

        def ensure_agent_note!
          return if @note.nil?
          return if @note.tags.pluck(:name).any? { |n| n.start_with?(AGENT_TAG_PREFIX) }

          render json: {
            error: "note #{@note.slug.inspect} does not carry an agent tag (prefix #{AGENT_TAG_PREFIX.inspect}). S2S activation is restricted to agent notes."
          }, status: :forbidden
        end

        def resolve_command(raw)
          key = raw.to_s.strip.downcase
          KNOWN_COMMANDS.fetch(key, KNOWN_COMMANDS.fetch("claude"))
        end

        def serialize(note, result, command:)
          session = result.session
          {
            tentacle_id: note.id,
            slug: note.slug,
            title: note.title,
            activated: true,
            reused: result.reused,
            pid: session&.pid,
            started_at: session&.started_at&.utc&.iso8601,
            command: command,
            routed_prompt_delivered: result.routed_prompt_delivered
          }
        end
      end
    end
  end
end
