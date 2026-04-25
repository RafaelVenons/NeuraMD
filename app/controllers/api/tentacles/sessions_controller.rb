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

        result = ::Tentacles::SessionControl.activate(
          note: @note,
          command: command,
          initial_prompt: params[:initial_prompt],
          persistence: {kind: "web", author_id: current_user&.id}
        )

        ::Tasks::ActivationNotifier.notify_if_external(
          target_note: @note,
          requested_by: params[:requested_by]
        )

        if result.reused
          render json: serialize_session(@note, result.session, reused: true, boot_config_applied: false, routed_prompt_delivered: result.routed_prompt_delivered), status: :ok
        else
          render json: serialize_session(@note, result.session, command_override: command, reused: false, boot_config_applied: true, routed_prompt_delivered: result.routed_prompt_delivered), status: :created
        end
      rescue ::Tentacles::SessionControl::InvalidBootConfig => e
        render json: {error: e.message}, status: :unprocessable_entity
      rescue ::Tentacles::SessionControl::StaleSession => e
        render json: {
          error: "session boot config is stale. DELETE /api/notes/#{@note.slug}/tentacle then POST again to recreate.",
          stale_boot_config: true,
          stale_reason: e.reason,
          current_cwd: e.current_cwd,
          desired_cwd: e.desired_cwd
        }, status: :conflict
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
