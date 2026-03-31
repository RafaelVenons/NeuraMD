module Properties
  module Types
    module MultiEnum
      def self.cast(raw, _config = {})
        return raw if raw.is_a?(Array)
        return raw.split(",").map(&:strip) if raw.is_a?(String)
        raw
      end

      def self.validate(value, config = {})
        errors = []
        unless value.is_a?(Array) && value.all? { |v| v.is_a?(String) }
          errors << "must be an array of strings"
          return errors
        end

        options = config["options"] || []
        invalid = value - options
        errors << "invalid values: #{invalid.join(", ")}. Must be from: #{options.join(", ")}" if invalid.any?
        errors
      end
    end
  end
end
