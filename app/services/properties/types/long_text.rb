module Properties
  module Types
    module LongText
      MAX_LENGTH = 10_000

      def self.cast(raw, _config = {})
        raw.to_s.strip
      end

      def self.normalize(value, _config = {})
        return value unless value.is_a?(String)
        value.strip
      end

      def self.validate(value, _config = {})
        errors = []
        errors << "must be a string" unless value.is_a?(String)
        errors << "is too long (max #{MAX_LENGTH} characters)" if value.is_a?(String) && value.length > MAX_LENGTH
        errors
      end
    end
  end
end
