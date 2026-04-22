module Neuramd
  module Exporter
    module Collectors
      # Counter of deploy events, labeled by outcome (clear | forced |
      # drained | aborted | recheck_failed | disabled | no_token |
      # endpoint_unreachable). Fed by post-receive POSTing to
      # /event/deploy — a missing event log just means no deploys were
      # recorded yet.
      class Deploy < Base
        KNOWN_OUTCOMES = %w[
          clear
          forced
          drained
          aborted
          recheck_failed
          disabled
          no_token
          endpoint_unreachable
        ].freeze

        def initialize(event_store:)
          @event_store = event_store
        end

        def collect
          events = @event_store.read("deploy")
          counts = Hash.new(0)
          KNOWN_OUTCOMES.each { |o| counts[o] = 0 }
          events.each do |event|
            outcome = event["outcome"].to_s
            next if outcome.empty?
            counts[outcome] += 1
          end

          [
            {
              name: "neuramd_deploy_count_total",
              type: "counter",
              help: "Deploy events recorded via /event/deploy, labeled by outcome.",
              samples: counts.map { |outcome, value| {labels: {outcome: outcome}, value: value} }
            }
          ]
        end
      end
    end
  end
end
