# Reattach to tentacle sessions that survived across a Puma restart.
#
# When NEURAMD_FEATURE_DTACH=on, shutdown_hooks detach instead of kill,
# so the detached children are still running under their dtach sessions
# when this process boots. bootstrap_sessions! scans TentacleSession
# records with status=alive and constructs a fresh local Session for
# each one whose socket + pid still check out.
#
# Runs asynchronously in a thread so boot is not blocked — a fresh
# spawn for the same tentacle_id during the reattach window is safe
# because SESSIONS is a Concurrent::Map and both paths check alive?
# before creating a duplicate.
#
# Gated to non-test environments to keep RSpec fast. Also a no-op when
# the dtach flag is off.
unless Rails.env.test?
  Rails.application.config.after_initialize do
    next unless defined?(::TentacleRuntime)
    next unless ::TentacleRuntime.dtach_enabled?

    Thread.new do
      Rails.application.executor.wrap do
        count = ::TentacleRuntime.bootstrap_sessions!
        Rails.logger.info("[tentacle_bootstrap] reattached #{count} session(s)") if count.positive?
      rescue StandardError => e
        Rails.logger.error("[tentacle_bootstrap] failed: #{e.class}: #{e.message}")
      end
    end
  end
end
