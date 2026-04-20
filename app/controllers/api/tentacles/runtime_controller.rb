module Api
  module Tentacles
    class RuntimeController < Api::BaseController
      before_action :ensure_tentacles_enabled!

      def index
        alive_ids = ::TentacleRuntime::SESSIONS.each_pair.filter_map do |id, session|
          next unless session&.alive?
          next unless Note.active.exists?(id: id)
          id
        end

        render json: {alive_ids: alive_ids}
      end

      private

      def ensure_tentacles_enabled!
        return if ::Tentacles::Authorization.enabled?

        render_forbidden
      end
    end
  end
end
