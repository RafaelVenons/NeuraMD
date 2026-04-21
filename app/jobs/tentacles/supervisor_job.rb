module Tentacles
  class SupervisorJob < ApplicationJob
    queue_as :default

    GRACE_PERIOD = 5.seconds

    def perform
      cutoff = Time.current - GRACE_PERIOD
      TentacleRuntime::SESSIONS.each_pair do |tentacle_id, session|
        next unless session
        next if session.alive?
        next if session.started_at && session.started_at > cutoff

        reap(tentacle_id)
      end
    end

    private

    def reap(tentacle_id)
      TentacleRuntime.stop(tentacle_id: tentacle_id)
    rescue StandardError => e
      Rails.logger.error("Tentacles::SupervisorJob failed to reap #{tentacle_id}: #{e.class}: #{e.message}")
    end
  end
end
