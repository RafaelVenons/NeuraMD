module Properties
  module Types
    module Text
      MAX_LENGTH = 500

      def self.cast(raw, _config = {})
        raw.to_s.strip
      end

      def self.normalize(value, _config = {})
        return value unless value.is_a?(String)
        value.strip
      end

      def self.validate(value, config = {})
        errors = []
        errors << "must be a string" unless value.is_a?(String)
        errors << "is too long (max #{MAX_LENGTH} characters)" if value.is_a?(String) && value.length > MAX_LENGTH
        return errors if errors.any?

        pattern_str = config.is_a?(Hash) ? config["pattern"] : nil
        if pattern_str.is_a?(String) && !pattern_str.empty?
          pattern = safe_regexp(pattern_str)
          errors << "must match the expected format" if pattern && !pattern.match?(value)
        end

        errors
      end

      # Defense in depth: PropertyDefinition validates `config.pattern` at
      # create/update (length cap + compile check). If a malformed or slow
      # pattern still reaches here (legacy data, direct SQL), compile with an
      # explicit timeout so catastrophic backtracking cannot stall requests.
      # Swallowing failures keeps writes functional — the PD-level validation
      # is the gate that should reject bad patterns.
      REGEXP_TIMEOUT_SECONDS = 0.1

      def self.safe_regexp(str)
        Regexp.new(str, timeout: REGEXP_TIMEOUT_SECONDS)
      rescue RegexpError
        nil
      end
    end
  end
end
