module ApiTokenAuth
  extend ActiveSupport::Concern

  ENV_TOKEN_KEY = "NEURAMD_DEPLOY_TOKEN".freeze
  ENV_TOKEN_FILE_KEY = "NEURAMD_DEPLOY_TOKEN_FILE".freeze

  private

  def ensure_api_token!
    expected = resolve_expected_token

    if expected.blank?
      Rails.logger.warn("[ApiTokenAuth] deploy token not configured in environment")
      render_error(
        status: :service_unavailable,
        code: "token_not_configured",
        message: "Internal API token not configured."
      )
      return false
    end

    provided = extract_bearer_token

    unless provided.present? &&
           provided.bytesize == expected.bytesize &&
           ActiveSupport::SecurityUtils.secure_compare(provided, expected)
      render_error(
        status: :unauthorized,
        code: "unauthorized",
        message: "Missing or invalid API token."
      )
      return false
    end

    true
  end

  def extract_bearer_token
    header = request.headers["Authorization"].to_s
    match = header.match(/\ABearer\s+(?<token>.+)\z/)
    match ? match[:token].strip : nil
  end

  def resolve_expected_token
    env_token = ENV[ENV_TOKEN_KEY].to_s.strip
    return env_token if env_token.present?

    file_path = ENV[ENV_TOKEN_FILE_KEY].to_s.strip
    return nil if file_path.blank?
    return nil unless File.readable?(file_path)

    File.read(file_path).strip.presence
  rescue StandardError => e
    Rails.logger.error("[ApiTokenAuth] failed to read token file: #{e.class}: #{e.message}")
    nil
  end
end
