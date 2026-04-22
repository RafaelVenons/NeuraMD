require "puma"
require "puma/server"

module Neuramd
  module Exporter
    # Thin wrapper over Puma::Server that wires the token middleware in
    # front of the Router and handles lifecycle (start / stop / join).
    class Server
      def initialize(host:, port:, event_store:, collectors:, token:)
        @host = host
        @port = port
        @event_store = event_store
        @collectors = collectors
        @token = token
        @server = nil
      end

      def run
        app = TokenAuth.new(
          Router.new(event_store: @event_store, collectors: @collectors),
          expected_token: @token
        )
        @server = Puma::Server.new(app, nil, min_threads: 1, max_threads: 5)
        @server.add_tcp_listener(@host, @port)
        log("listening on http://#{@host}:#{@port}")
        thread = @server.run
        thread.join if thread
      end

      def stop
        return unless @server
        log("shutting down")
        @server.stop(true)
      end

      private

      def log(message)
        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger.info("[exporter] #{message}")
        else
          warn "[exporter] #{message}"
        end
      end
    end
  end
end
