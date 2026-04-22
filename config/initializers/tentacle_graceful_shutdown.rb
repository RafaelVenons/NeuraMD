# Shut down live tentacle sessions when the Rails process exits cleanly.
#
# Covers the systemd-triggered SIGTERM path — Puma installs its own
# SIGTERM handler that runs a graceful request shutdown and then returns
# from its main loop, which lets Ruby finalize via at_exit. For
# `bin/rails restart` and `pumactl restart` the hook is additionally
# wired through Puma's `on_restart` DSL in config/puma.rb.
#
# When NEURAMD_FEATURE_DTACH=on the dispatch detaches without killing so
# the next boot can reattach. With the flag off the legacy kill-and-
# persist path runs unchanged.
#
# Skipped in the test env so RSpec's process exit is not slowed by an
# (empty) scan of TentacleRuntime::SESSIONS. Still a no-op at runtime if
# SESSIONS is empty, so this is mostly a speed optimisation for specs.
unless Rails.env.test?
  at_exit do
    next unless defined?(::TentacleRuntime)

    begin
      ids = ::TentacleRuntime.shutdown!(grace: 10)
      if ids&.any?
        verb = ::TentacleRuntime.dtach_enabled? ? "detached" : "drained"
        Rails.logger.info("[tentacle_shutdown] #{verb} #{ids.size} tentacle(s) on exit")
      end
    rescue StandardError => e
      warn "[tentacle_shutdown] #{e.class}: #{e.message}"
    end
  end
end
