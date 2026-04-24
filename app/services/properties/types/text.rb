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

      # Malformed pattern config is a seeder/migration bug, not a write-time
      # concern. Logging here would fire on every validation call; swallow and
      # let the seeder spec catch invalid patterns instead.
      def self.safe_regexp(str)
        Regexp.new(str)
      rescue RegexpError
        nil
      end
    end
  end
end
