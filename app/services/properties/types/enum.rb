module Properties
  module Types
    module Enum
      def self.cast(raw, _config = {})
        raw.to_s.strip
      end

      def self.validate(value, config = {})
        errors = []
        unless value.is_a?(String)
          errors << "must be a string"
          return errors
        end

        options = config["options"] || []
        errors << "must be one of: #{options.join(", ")}" unless options.include?(value)
        errors
      end
    end
  end
end
