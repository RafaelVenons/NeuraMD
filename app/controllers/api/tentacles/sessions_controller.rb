module Api
  module Tentacles
    class SessionsController < Api::BaseController
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

        existing = ::TentacleRuntime.get(@note.id)
        if existing&.alive?
          render json: serialize_session(@note, existing, reused: true, boot_config_applied: false), status: :ok
          return
        end

        repo_root, initial_prompt = sanitized_boot_config(@note)
        cwd = WorktreeService.ensure(tentacle_id: @note.id, repo_root: repo_root)
        note = @note
        author = current_user
        session = ::TentacleRuntime.start(
          tentacle_id: @note.id,
          command: command,
          cwd: cwd,
          initial_prompt: initial_prompt,
          on_exit: ->(transcript:, command:, started_at:, ended_at:, **) do
            ::Tentacles::TranscriptService.persist(
              note: note,
              transcript: transcript,
              command: command,
              started_at: started_at,
              ended_at: ended_at,
              author: author
            )
          end
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

      def sanitized_boot_config(note)
        props = note.current_properties
        canonical_cwd, cwd_err = ::Tentacles::BootConfig.canonicalize_cwd(props["tentacle_cwd"])
        if cwd_err && props["tentacle_cwd"].present?
          Rails.logger.warn("Tentacle #{note.id} tentacle_cwd rejected at session start: #{cwd_err}")
        end

        validated_prompt, prompt_err = ::Tentacles::BootConfig.validate_initial_prompt(props["tentacle_initial_prompt"])
        if prompt_err
          Rails.logger.warn("Tentacle #{note.id} tentacle_initial_prompt rejected at session start: #{prompt_err}")
        end

        [canonical_cwd || Rails.root, validated_prompt]
      end

      def resolve_command(raw)
        key = raw.to_s.strip.downcase
        KNOWN_COMMANDS.fetch(key, KNOWN_COMMANDS.fetch("bash"))
      end

      def serialize_session(note, session, command_override: nil, reused: nil, boot_config_applied: nil)
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
        payload
      end
    end
  end
end
