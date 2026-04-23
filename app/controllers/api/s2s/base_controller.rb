module Api
  module S2s
    # Base for service-to-service endpoints used by tentacle agents.
    # No Devise/Pundit — agents spawn inside Rails but don't carry a
    # human's session cookie. Auth via shared token in the
    # X-NeuraMD-Agent-Token header, compared against
    # Rails.application.credentials.agent_s2s_token.
    #
    # Skips CSRF (API endpoint, token-authenticated) and bypasses the
    # human-auth cookie path inherited from ApplicationController.
    class BaseController < ActionController::API
      TOKEN_HEADER = "HTTP_X_NEURAMD_AGENT_TOKEN".freeze

      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

      before_action :authenticate_agent_token!
      before_action :ensure_tentacles_enabled!

      private

      def authenticate_agent_token!
        configured = ::Rails.application.credentials.agent_s2s_token
        if configured.blank?
          render json: {error: "S2S token not configured"}, status: :service_unavailable
          return
        end

        presented = request.headers[TOKEN_HEADER].to_s
        if presented.empty? || !ActiveSupport::SecurityUtils.secure_compare(presented, configured.to_s)
          render json: {error: "invalid or missing X-NeuraMD-Agent-Token"}, status: :unauthorized
          nil
        end
      end

      def ensure_tentacles_enabled!
        return if ::Tentacles::Authorization.enabled?

        render json: {error: "tentacles feature is disabled"}, status: :forbidden
      end

      def render_not_found(error = nil)
        render json: {error: error&.message.presence || "Resource not found."}, status: :not_found
      end
    end
  end
end
