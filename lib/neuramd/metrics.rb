require "json"
require "net/http"
require "uri"
require "thread"

module Neuramd
  # Fire-and-forget HTTP client that POSTs domain events to the local
  # neuramd-metrics-exporter. Callers do not wait for the response.
  #
  # Design: bounded SizedQueue + single persistent worker thread.
  # Spawning a fresh Thread per emit (the old approach) let a slow or
  # unreachable exporter exhaust the process thread budget under load.
  # When the queue is full we drop the event, bump a counter, and log.
  # Dropped handles are pre-signaled so callers awaiting join never hang.
  #
  # Feature-gated by NEURAMD_METRICS_URL — unset or blank means no-op.
  module Metrics
    DEFAULT_TIMEOUT = 2
    QUEUE_CAPACITY = 256
    ENV_URL_KEY = "NEURAMD_METRICS_URL".freeze
    ENV_TOKEN_KEY = "NEURAMD_DEPLOY_TOKEN".freeze
    ENV_TOKEN_FILE_KEY = "NEURAMD_DEPLOY_TOKEN_FILE".freeze

    WORKER_MUTEX = Mutex.new
    DROP_MUTEX = Mutex.new

    class Handle
      def initialize
        @mutex = Mutex.new
        @cv = ConditionVariable.new
        @done = false
      end

      def signal!
        @mutex.synchronize do
          @done = true
          @cv.broadcast
        end
      end

      def wait(timeout = nil)
        deadline = timeout ? Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout : nil
        @mutex.synchronize do
          until @done
            if deadline
              remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
              break if remaining <= 0
              @cv.wait(@mutex, remaining)
            else
              @cv.wait(@mutex)
            end
          end
          return nil unless @done
        end
        self
      end

      alias_method :join, :wait
    end

    class << self
      def emit(type, payload = {})
        return nil unless enabled?

        ensure_worker!
        handle = Handle.new
        job = [type.to_s, JSON.generate(payload || {}), base_url, bearer_header, handle]

        begin
          @queue.push(job, true)
        rescue ThreadError
          handle.signal!
          record_drop!(type)
          return handle
        end

        handle
      end

      def enabled?
        !base_url.empty?
      end

      def base_url
        ENV[ENV_URL_KEY].to_s.strip
      end

      def drop_count
        DROP_MUTEX.synchronize { @drop_count.to_i }
      end

      def worker_count
        (@worker&.alive? ? 1 : 0)
      end

      def reset_for_tests!
        WORKER_MUTEX.synchronize do
          @worker&.kill
          @worker&.join(1)
          @worker = nil
          @queue = nil
        end
        DROP_MUTEX.synchronize { @drop_count = 0 }
      end

      private

      def ensure_worker!
        return if @worker&.alive?

        WORKER_MUTEX.synchronize do
          next if @worker&.alive?
          @queue ||= SizedQueue.new(QUEUE_CAPACITY)
          @worker = Thread.new { run_loop }
        end
      end

      def run_loop
        loop do
          job = @queue.pop
          break if job.nil?
          type, body, url, auth, handle = job
          begin
            deliver(url, type, body, auth)
          rescue StandardError => e
            log_warn("emit(#{type}) failed: #{e.class}: #{e.message}")
          ensure
            handle.signal!
          end
        end
      end

      def deliver(url, type, body, auth_header)
        uri = URI.join(ensure_trailing_slash(url), "event/#{type}")
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request["Authorization"] = auth_header if auth_header
        request.body = body

        Net::HTTP.start(uri.host, uri.port, open_timeout: DEFAULT_TIMEOUT, read_timeout: DEFAULT_TIMEOUT) do |http|
          http.request(request)
        end
      end

      def record_drop!(type)
        new_count = DROP_MUTEX.synchronize do
          @drop_count ||= 0
          @drop_count += 1
        end
        log_warn("emit(#{type}) dropped (queue full); total_drops=#{new_count}") if new_count == 1 || (new_count % 100).zero?
      end

      def bearer_header
        token = resolve_token
        token.empty? ? nil : "Bearer #{token}"
      end

      def resolve_token
        env_token = ENV[ENV_TOKEN_KEY].to_s.strip
        return env_token unless env_token.empty?

        file_path = ENV[ENV_TOKEN_FILE_KEY].to_s.strip
        return "" if file_path.empty? || !File.readable?(file_path)

        File.read(file_path).strip
      rescue StandardError
        ""
      end

      def ensure_trailing_slash(url)
        url.end_with?("/") ? url : "#{url}/"
      end

      def log_warn(message)
        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger.warn("[metrics] #{message}")
        else
          warn "[metrics] #{message}"
        end
      end
    end
  end
end
