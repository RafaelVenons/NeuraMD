module Tentacles
  module BootConfig
    DEFAULT_CWD_ALLOWED_PREFIXES = ["/home/venom/projects/"].freeze
    INITIAL_PROMPT_MAX_BYTES = 2048

    module_function

    def allowed_cwd_prefixes
      raw = ENV["NEURAMD_TENTACLE_CWD_ROOTS"].to_s
      return DEFAULT_CWD_ALLOWED_PREFIXES if raw.strip.empty?

      raw.split(",").map(&:strip).reject(&:empty?).map { |p| p.end_with?("/") ? p : "#{p}/" }
    end

    def canonicalize_cwd(value)
      return [nil, nil] if value.nil? || value.to_s.strip.empty?
      return [nil, "cwd must be an absolute path"] unless value.start_with?("/")

      canonical = begin
        File.realpath(value)
      rescue Errno::ENOENT, Errno::ENOTDIR
        return [nil, "cwd directory does not exist: #{value}"]
      end

      return [nil, "cwd directory does not exist: #{value}"] unless File.directory?(canonical)

      prefixes = allowed_cwd_prefixes
      unless prefixes.any? { |prefix| canonical.start_with?(prefix) }
        return [nil, "cwd must be under one of: #{prefixes.join(", ")}"]
      end

      [canonical, nil]
    end

    def validate_initial_prompt(value)
      return [nil, nil] if value.nil? || value.to_s.empty?

      if value.bytesize > INITIAL_PROMPT_MAX_BYTES
        return [nil, "initial_prompt exceeds #{INITIAL_PROMPT_MAX_BYTES} bytes (got #{value.bytesize})"]
      end

      [value, nil]
    end
  end
end
