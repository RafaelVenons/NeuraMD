module Api
  class FailureApp < Devise::FailureApp
    def respond
      return json_error_response if request.format.json? || request.path.start_with?("/api/")

      super
    end

    private

    def json_error_response
      self.status = 401
      self.content_type = "application/json"
      self.response_body = {
        error: {
          code: "unauthorized",
          message: i18n_message.presence || "You must be signed in."
        }
      }.to_json
    end
  end
end
