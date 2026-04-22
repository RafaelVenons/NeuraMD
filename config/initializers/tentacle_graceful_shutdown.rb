# Drain live tentacle PTY sessions when the Rails process exits cleanly.
#
# Covers the systemd-triggered SIGTERM path — Puma installs its own SIGTERM
# handler that runs a graceful request shutdown and then returns from its
# main loop, which lets Ruby finalize via at_exit. For `bin/rails restart`
# and `pumactl restart` the drain is additionally wired through Puma's
# `on_restart` DSL hook in config/puma.rb.
#
# Skipped in the test env so RSpec's process exit is not slowed by an
# (empty) scan of TentacleRuntime::SESSIONS. Still a no-op at runtime if
# SESSIONS is empty, so this is mostly a speed optimisation for specs.
unless Rails.env.test?
  at_exit do
    next unless defined?(::TentacleRuntime)

    begin
      stopped = ::TentacleRuntime.graceful_stop_all(grace: 10)
      Rails.logger.info("[tentacle_shutdown] drained #{stopped.size} tentacle(s) on exit") if stopped.any?
    rescue StandardError => e
      warn "[tentacle_shutdown] #{e.class}: #{e.message}"
    end
  end
end
