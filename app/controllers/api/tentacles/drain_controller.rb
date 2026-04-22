module Api
  module Tentacles
    class DrainController < Api::BaseController
      include ApiTokenAuth

      NOTICE_SECONDS_MIN = 0
      NOTICE_SECONDS_MAX = 600
      DEFAULT_NOTICE_SECONDS = 30
      ALLOWED_MODES = %w[warn force].freeze
      DEFAULT_MODE = "warn".freeze
      DEFAULT_FORCE_GRACE = 10

      skip_before_action :authenticate_user!, raise: false
      skip_before_action :verify_authenticity_token, raise: false

      before_action :ensure_tentacles_enabled!
      before_action :ensure_api_token!

      def create
        notice_seconds = coerce_notice_seconds(params[:notice_seconds])
        mode = coerce_mode(params[:mode])

        alive_ids = collect_alive_ids
        now = Time.current
        deadline = now + notice_seconds.seconds
        stopped_ids = []

        if alive_ids.any?
          # notice_seconds == 0 acts as a probe regardless of mode — returns
          # alive_ids without broadcasting. Used by the deploy gate to poll
          # liveness before and after a warn window.
          broadcast_notice(alive_ids, deadline) unless notice_seconds.zero?
          stopped_ids = ::TentacleRuntime.graceful_stop_all(grace: DEFAULT_FORCE_GRACE) if mode == "force"
        end

        render json: {
          mode: mode,
          notice_seconds: notice_seconds,
          alive_ids: alive_ids,
          stopped_ids: stopped_ids,
          warned_at: alive_ids.any? ? now.utc.iso8601 : nil,
          deadline_at: alive_ids.any? ? deadline.utc.iso8601 : nil
        }
      end

      private

      def ensure_tentacles_enabled!
        return if ::Tentacles::Authorization.enabled?

        render_forbidden
      end

      def coerce_notice_seconds(raw)
        value = Integer(raw.to_s, 10)
        value.clamp(NOTICE_SECONDS_MIN, NOTICE_SECONDS_MAX)
      rescue ArgumentError, TypeError
        DEFAULT_NOTICE_SECONDS
      end

      def coerce_mode(raw)
        mode = raw.to_s.strip.downcase
        ALLOWED_MODES.include?(mode) ? mode : DEFAULT_MODE
      end

      def collect_alive_ids
        ::TentacleRuntime::SESSIONS.each_pair.filter_map do |id, session|
          session&.alive? ? id.to_s : nil
        end
      end

      def broadcast_notice(alive_ids, deadline)
        deadline_iso = deadline.utc.iso8601
        alive_ids.each do |id|
          ::TentacleChannel.broadcast_deploy_notice(
            tentacle_id: id,
            deadline_at: deadline_iso
          )
        end
      end
    end
  end
end
