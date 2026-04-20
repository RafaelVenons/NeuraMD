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
        cwd = WorktreeService.ensure(tentacle_id: @note.id)
        note = @note
        author = current_user
        session = ::TentacleRuntime.start(
          tentacle_id: @note.id,
          command: command,
          cwd: cwd,
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
        render json: serialize_session(@note, session, command_override: command), status: :created
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

      def serialize_session(note, session, command_override: nil)
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
      end
    end
  end
end
