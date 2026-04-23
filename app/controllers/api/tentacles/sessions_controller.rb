module Api
  module Tentacles
    class SessionsController < Api::BaseController
      class InvalidBootConfig < StandardError; end

      KNOWN_COMMANDS = {
        "bash" => ["bash", "-l"],
        "claude" => ["claude"]
      }.freeze

      before_action :ensure_tentacles_enabled!
      before_action :set_note, except: :index

      def index
        sessions = ::TentacleRuntime::SESSIONS.each_pair.filter_map do |id, session|
          next unless session&.alive?
          note = Note.active.find_by(id: id)
          next unless note
          serialize_session(note, session)
        end
        sessions.sort_by! { |s| s[:started_at] || "" }
        render json: {sessions: sessions.reverse}
      end

      def show
        authorize @note, :show?
        render json: serialize_session(@note, ::TentacleRuntime.get(@note.id))
      end

      def create
        authorize @note, :update?
        command = resolve_command(params[:command])

        routed_prompt, routed_err = ::Tentacles::BootConfig.validate_initial_prompt(params[:initial_prompt])
        if routed_err
          render json: {error: routed_err}, status: :unprocessable_entity
          return
        end

        existing = ::TentacleRuntime.get(@note.id)
        if existing&.alive?
          if routed_prompt.present?
            ::TentacleRuntime.write(tentacle_id: @note.id, data: "#{routed_prompt}\n")
          end
          render json: serialize_session(@note, existing, reused: true, boot_config_applied: false, routed_prompt_delivered: routed_prompt.present?), status: :ok
          return
        end

        begin
          repo_root, worktree_root, link_shared, boot_prompt = sanitized_boot_config(@note)
        rescue InvalidBootConfig => e
          render json: {error: e.message}, status: :unprocessable_entity
          return
        end
        initial_prompt = merge_prompts(boot_prompt, routed_prompt)
        cwd = WorktreeService.ensure(
          tentacle_id: @note.id,
          repo_root: repo_root,
          worktree_root: worktree_root,
          link_shared: link_shared
        )
        session = ::TentacleRuntime.start(
          tentacle_id: @note.id,
          command: command,
          cwd: cwd,
          initial_prompt: initial_prompt,
          persistence: {kind: "web", author_id: current_user&.id}
        )
        render json: serialize_session(@note, session, command_override: command, reused: false, boot_config_applied: true), status: :created
      end

      def destroy
        authorize @note, :update?
        ::TentacleRuntime.stop(tentacle_id: @note.id)
        render json: {stopped: true}
      end

      private

      def ensure_tentacles_enabled!
        return if ::Tentacles::Authorization.enabled?

        render_forbidden
      end

      def set_note
        @note = Note.active.find_by(slug: params[:slug])
        render_not_found unless @note
      end

      def merge_prompts(boot, routed)
        return boot if routed.nil? || routed.empty?
        return routed if boot.nil? || boot.empty?
        "#{boot}\n\n#{routed}"
      end

      def sanitized_boot_config(note)
        props = note.current_properties

        # When tentacle_workspace is declared on the note, it is the binding
        # runtime contract: resolve-or-fail-closed. The old behaviour of
        # logging a warning and falling back to tentacle_cwd is an attractive
        # nuisance — a stale cwd could send commits to a completely different
        # repo without any user signal. Raise so the controller can 422.
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

      def resolve_command(raw)
        key = raw.to_s.strip.downcase
        KNOWN_COMMANDS.fetch(key, KNOWN_COMMANDS.fetch("bash"))
      end

      def serialize_session(note, session, command_override: nil, reused: nil, boot_config_applied: nil, routed_prompt_delivered: nil)
        payload =
          if session&.alive?
            {
              tentacle_id: note.id,
              slug: note.slug,
              title: note.title,
              alive: true,
              pid: session.pid,
              started_at: session.started_at&.utc&.iso8601,
              command: command_override || session.instance_variable_get(:@command)
            }
          else
            {
              tentacle_id: note.id,
              slug: note.slug,
              title: note.title,
              alive: false,
              pid: nil,
              started_at: nil,
              command: nil
            }
          end

        payload[:reused] = reused unless reused.nil?
        payload[:boot_config_applied] = boot_config_applied unless boot_config_applied.nil?
        payload[:routed_prompt_delivered] = routed_prompt_delivered unless routed_prompt_delivered.nil?
        payload
      end
    end
  end
end
