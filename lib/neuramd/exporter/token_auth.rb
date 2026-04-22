require "json"

module Neuramd
  module Exporter
    # Rack middleware that protects event-submission endpoints with a
    # bearer token. /metrics and /health stay open — they are bound to
    # localhost and only expose aggregate counts.
    class TokenAuth
      PROTECTED_PREFIX = "/event/".freeze

      def initialize(app, expected_token:)
        @app = app
        @expected = expected_token.to_s
      end

      def call(env)
        path = env["PATH_INFO"].to_s
        return @app.call(env) unless path.start_with?(PROTECTED_PREFIX)

        if @expected.empty?
          return unauthorized("token_not_configured", 503, "Internal deploy token not configured.")
        end

        provided = extract_bearer(env["HTTP_AUTHORIZATION"])
        return unauthorized("unauthorized", 401, "Missing or invalid API token.") unless provided
        return unauthorized("unauthorized", 401, "Missing or invalid API token.") unless timing_safe_eq(provided, @expected)

        @app.call(env)
      end

      private

      def extract_bearer(header)
        return nil if header.nil?
        match = header.to_s.match(/\ABearer\s+(.+)\z/)
        match ? match[1].strip : nil
      end

      def timing_safe_eq(a, b)
        return false if a.nil? || b.nil?
        return false if a.bytesize != b.bytesize
        result = 0
        a.bytes.zip(b.bytes) { |x, y| result |= x ^ y }
        result.zero?
      end

      def unauthorized(code, status, message)
        body = JSON.generate(error: {code: code, message: message})
        [status, {"content-type" => "application/json"}, [body]]
      end
    end
  end
end
