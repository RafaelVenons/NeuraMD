require "json"
require "net/http"
require "uri"

module Neuramd
  # Fire-and-forget HTTP client that POSTs domain events to the local
  # neuramd-metrics-exporter. Callers do not wait for the response —
  # each emit spawns a short-lived thread with a 2s timeout so the
  # main request path is never blocked by the exporter being slow.
  #
  # Feature-gated by NEURAMD_METRICS_URL — unset or blank means no-op,
  # so this stays inert in environments without the exporter running.
  module Metrics
    DEFAULT_TIMEOUT = 2
    ENV_URL_KEY = "NEURAMD_METRICS_URL".freeze
    ENV_TOKEN_KEY = "NEURAMD_DEPLOY_TOKEN".freeze
    ENV_TOKEN_FILE_KEY = "NEURAMD_DEPLOY_TOKEN_FILE".freeze

    class << self
      # Public entry point. Returns the thread handle so specs can join,
      # but production callers should treat it as void.
      def emit(type, payload = {})
        return nil unless enabled?

        url = base_url
        auth = bearer_header
        body = JSON.generate(payload || {})

        Thread.new do
          deliver(url, type, body, auth)
        rescue StandardError => e
          log_warn("emit(#{type}) failed: #{e.class}: #{e.message}")
        end
      end

      def enabled?
        !base_url.empty?
      end

      def base_url
        ENV[ENV_URL_KEY].to_s.strip
      end

      private

      def deliver(url, type, body, auth_header)
        uri = URI.join(ensure_trailing_slash(url), "event/#{type}")
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request["Authorization"] = auth_header if auth_header
        request.body = body

        Net::HTTP.start(uri.host, uri.port, open_timeout: DEFAULT_TIMEOUT, read_timeout: DEFAULT_TIMEOUT) do |http|
          http.request(request)
        end
      end

      def bearer_header
        token = resolve_token
        token.empty? ? nil : "Bearer #{token}"
      end

      def resolve_token
        env_token = ENV[ENV_TOKEN_KEY].to_s.strip
        return env_token unless env_token.empty?

        file_path = ENV[ENV_TOKEN_FILE_KEY].to_s.strip
        return "" if file_path.empty? || !File.readable?(file_path)

        File.read(file_path).strip
      rescue StandardError
        ""
      end

      def ensure_trailing_slash(url)
        url.end_with?("/") ? url : "#{url}/"
      end

      def log_warn(message)
        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger.warn("[metrics] #{message}")
        else
          warn "[metrics] #{message}"
        end
      end
    end
  end
end
