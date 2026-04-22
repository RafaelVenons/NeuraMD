module Neuramd
  module Exporter
    DEFAULT_HOST = "127.0.0.1".freeze
    DEFAULT_PORT = 9100
    DEFAULT_STATE_DIR = "/var/lib/neuramd-exporter".freeze

    def self.start
      host = ENV.fetch("NEURAMD_EXPORTER_HOST", DEFAULT_HOST)
      port = ENV.fetch("NEURAMD_EXPORTER_PORT", DEFAULT_PORT).to_i
      state_dir = ENV.fetch("NEURAMD_EXPORTER_STATE_DIR", DEFAULT_STATE_DIR)
      token = resolve_token

      event_store = EventStore.new(base_dir: File.join(state_dir, "events"))
      collectors = build_collectors(event_store)

      server = Server.new(
        host: host,
        port: port,
        event_store: event_store,
        collectors: collectors,
        token: token
      )

      Signal.trap("TERM") { server.stop }
      Signal.trap("INT")  { server.stop }
      server.run
    end

    def self.resolve_token
      env_token = ENV["NEURAMD_DEPLOY_TOKEN"].to_s.strip
      return env_token if env_token.present?

      file_path = ENV["NEURAMD_DEPLOY_TOKEN_FILE"].to_s.strip
      return "" if file_path.empty? || !File.readable?(file_path)

      File.read(file_path).strip
    rescue StandardError => e
      Rails.logger.warn("[exporter] token resolution failed: #{e.class}: #{e.message}") if defined?(Rails)
      ""
    end

    def self.build_collectors(event_store)
      [
        Collectors::Notes.new,
        Collectors::Deploy.new(event_store: event_store),
        Collectors::Tentacles.new(event_store: event_store)
      ]
    end
  end
end

require_relative "exporter/formatter"
require_relative "exporter/event_store"
require_relative "exporter/token_auth"
require_relative "exporter/router"
require_relative "exporter/server"
require_relative "exporter/collectors/base"
require_relative "exporter/collectors/notes"
require_relative "exporter/collectors/deploy"
require_relative "exporter/collectors/tentacles"
