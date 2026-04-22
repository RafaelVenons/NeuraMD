require "json"

module Neuramd
  module Exporter
    # Plain Rack app with a handful of routes. Intentionally no
    # Rack::Builder — the endpoint list is small and static, so a single
    # `call` method keeps the flow obvious.
    class Router
      NOT_FOUND_BODY = "not found\n".freeze
      METHOD_NOT_ALLOWED_BODY = "method not allowed\n".freeze

      def initialize(event_store:, collectors:)
        @event_store = event_store
        @collectors = collectors
      end

      def call(env)
        method = env["REQUEST_METHOD"].to_s.upcase
        path = env["PATH_INFO"].to_s

        if path == "/metrics"
          return respond_not_allowed unless method == "GET"
          return render_metrics
        end

        if path == "/health"
          return respond_not_allowed unless method == "GET"
          return [200, {"content-type" => "text/plain"}, ["ok\n"]]
        end

        if path.start_with?("/event/")
          return respond_not_allowed unless method == "POST"
          type = path.sub(%r{\A/event/}, "")
          return record_event(type, env)
        end

        [404, {"content-type" => "text/plain"}, [NOT_FOUND_BODY]]
      end

      private

      def render_metrics
        metrics = @collectors.flat_map do |collector|
          collector.collect
        rescue StandardError => e
          warn "[exporter] collector #{collector.class} failed: #{e.class}: #{e.message}"
          []
        end
        body = Formatter.format(metrics)
        [200, {"content-type" => Formatter::CONTENT_TYPE}, [body]]
      end

      def record_event(type, env)
        return [400, json_ct, [json_error("invalid_type", "Event type is blank.")]] if type.empty?

        raw = env["rack.input"]&.read.to_s
        payload =
          if raw.empty?
            {}
          else
            begin
              parsed = JSON.parse(raw)
              parsed.is_a?(Hash) ? parsed : {"value" => parsed}
            rescue JSON::ParserError
              return [400, json_ct, [json_error("invalid_json", "Body is not valid JSON.")]]
            end
          end

        begin
          @event_store.append(type, payload)
        rescue ArgumentError => e
          return [400, json_ct, [json_error("invalid_type", e.message)]]
        end

        [204, {"content-type" => "text/plain"}, []]
      end

      def respond_not_allowed
        [405, {"content-type" => "text/plain"}, [METHOD_NOT_ALLOWED_BODY]]
      end

      def json_ct
        {"content-type" => "application/json"}
      end

      def json_error(code, message)
        JSON.generate(error: {code: code, message: message})
      end
    end
  end
end
