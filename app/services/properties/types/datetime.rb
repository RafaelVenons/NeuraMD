module Properties
  module Types
    module Datetime
      ISO_PATTERN = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/

      def self.cast(raw, _config = {})
        return raw if raw.is_a?(String) && raw.match?(ISO_PATTERN)

        parsed = Time.parse(raw.to_s)
        parsed.utc.iso8601
      rescue ArgumentError, TypeError
        raw
      end

      def self.validate(value, _config = {})
        errors = []
        unless value.is_a?(String) && value.match?(ISO_PATTERN)
          errors << "must be an ISO 8601 datetime"
          return errors
        end

        Time.parse(value)
        errors
      rescue ArgumentError
        errors << "is not a valid datetime"
        errors
      end
    end
  end
end
