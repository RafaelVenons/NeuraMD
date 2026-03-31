module Properties
  module Types
    module Date
      def self.cast(raw, _config = {})
        return raw if raw.is_a?(String) && raw.match?(/\A\d{4}-\d{2}-\d{2}\z/)

        parsed = ::Date.parse(raw.to_s)
        parsed.iso8601
      rescue ::Date::Error, TypeError
        raw
      end

      def self.normalize(value, _config = {})
        return value unless value.is_a?(String)
        parsed = ::Date.parse(value)
        parsed.iso8601
      rescue ::Date::Error
        value
      end

      def self.validate(value, _config = {})
        errors = []
        unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
          errors << "must be an ISO 8601 date (YYYY-MM-DD)"
          return errors
        end

        ::Date.parse(value)
        errors
      rescue ::Date::Error
        errors << "is not a valid date"
        errors
      end
    end
  end
end
