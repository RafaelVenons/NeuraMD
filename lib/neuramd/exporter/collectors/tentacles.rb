module Neuramd
  module Exporter
    module Collectors
      # Tentacle lifecycle counters fed from /event/tentacle_spawn,
      # /event/tentacle_exit, and /event/transcript_persist. The
      # 'alive' gauge is intentionally NOT exported — Prometheus
      # prefers monotonic counters and 'alive' can be derived as
      # rate(spawn) - rate(exit) at query time.
      class Tentacles < Base
        def initialize(event_store:)
          @event_store = event_store
        end

        def collect
          [
            simple_counter(
              name: "neuramd_tentacles_spawned_total",
              help: "Tentacle PTY sessions that were started.",
              events: @event_store.read("tentacle_spawn")
            ),
            labeled_counter(
              name: "neuramd_tentacles_exited_total",
              help: "Tentacle PTY sessions that ended, labeled by reason.",
              events: @event_store.read("tentacle_exit"),
              label: :reason,
              known_values: %w[graceful signal forced crash unknown]
            ),
            labeled_counter(
              name: "neuramd_transcripts_persisted_total",
              help: "Transcript persist attempts labeled by outcome.",
              events: @event_store.read("transcript_persist"),
              label: :outcome,
              known_values: %w[ok error]
            )
          ]
        end

        private

        def simple_counter(name:, help:, events:)
          {
            name: name,
            type: "counter",
            help: help,
            samples: [{value: events.size}]
          }
        end

        def labeled_counter(name:, help:, events:, label:, known_values:)
          counts = Hash.new(0)
          known_values.each { |v| counts[v] = 0 }
          events.each do |event|
            value = event[label.to_s].to_s
            value = "unknown" if value.empty?
            counts[value] += 1
          end
          {
            name: name,
            type: "counter",
            help: help,
            samples: counts.map { |v, n| {labels: {label => v}, value: n} }
          }
        end
      end
    end
  end
end
