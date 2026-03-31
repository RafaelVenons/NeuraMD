module Properties
  module Types
    module Url
      def self.cast(raw, _config = {})
        raw.to_s.strip
      end

      def self.validate(value, _config = {})
        errors = []
        unless value.is_a?(String)
          errors << "must be a string"
          return errors
        end

        uri = URI.parse(value)
        errors << "must be a valid URL with scheme" unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        errors
      rescue URI::InvalidURIError
        errors << "is not a valid URL"
        errors
      end
    end
  end
end
