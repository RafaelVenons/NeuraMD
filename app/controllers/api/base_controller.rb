module Api
  class BaseController < ApplicationController
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
    rescue_from ActionController::ParameterMissing, with: :render_invalid_params
    rescue_from Pundit::NotAuthorizedError, with: :render_forbidden

    def not_found
      render_not_found
    end

    private

    def render_error(status:, code:, message:, details: nil)
      render json: {error: {code: code, message: message, details: details}.compact}, status: status
    end

    def render_not_found(error = nil)
      render_error(status: :not_found, code: "not_found", message: error&.message.presence || "Resource not found.")
    end

    def render_invalid_params(error)
      render_error(status: :unprocessable_entity, code: "invalid_params", message: error.message)
    end

    def render_forbidden(_error = nil)
      render_error(status: :forbidden, code: "forbidden", message: "You are not allowed to perform this action.")
    end
  end
end
