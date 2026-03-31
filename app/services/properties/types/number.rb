module Properties
  module Types
    module Number
      def self.cast(raw, _config = {})
        return raw if raw.is_a?(Numeric)
        return nil if raw.to_s.strip.empty?

        str = raw.to_s.strip
        str.include?(".") ? Float(str) : Integer(str)
      rescue ArgumentError, TypeError
        raw
      end

      def self.validate(value, config = {})
        errors = []
        unless value.is_a?(Numeric)
          errors << "must be a number"
          return errors
        end

        min = config["min"]
        max = config["max"]
        errors << "must be >= #{min}" if min && value < min
        errors << "must be <= #{max}" if max && value > max
        errors
      end
    end
  end
end
