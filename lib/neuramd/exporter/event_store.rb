require "fileutils"
require "json"
require "pathname"

module Neuramd
  module Exporter
    # Append-only JSONL event log. One file per event type under base_dir.
    # Collectors read the file to derive counters; POST /event/<type>
    # appends a new line with the submitted payload + a recorded_at ts.
    #
    # This is intentionally dumb — no rotation, no compaction. Event
    # volume is low (deploy events ≈ 10/day, tentacle events ≈ 100/day).
    # Rotation policy can be bolted on later via logrotate if needed.
    class EventStore
      VALID_TYPE = /\A[a-z0-9_]+\z/i.freeze

      def initialize(base_dir:)
        @base_dir = Pathname.new(base_dir)
        @mutex = Mutex.new
      end

      def append(type, payload)
        key = sanitize_type!(type)
        path = path_for(key)
        line = JSON.generate(payload.merge("recorded_at" => Time.now.utc.iso8601))
        @mutex.synchronize do
          FileUtils.mkdir_p(@base_dir)
          File.open(path, "a") { |f| f.puts(line) }
        end
      end

      def read(type)
        key = sanitize_type!(type)
        path = path_for(key)
        return [] unless path.exist?
        path.each_line.filter_map do |line|
          JSON.parse(line)
        rescue JSON::ParserError
          nil
        end
      end

      private

      def sanitize_type!(type)
        key = type.to_s.strip
        raise ArgumentError, "invalid event type: #{type.inspect}" unless VALID_TYPE.match?(key)
        key
      end

      def path_for(key)
        @base_dir.join("#{key}.jsonl")
      end
    end
  end
end
