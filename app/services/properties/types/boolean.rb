module Properties
  module Types
    module Boolean
      TRUTHY = %w[true 1 yes on].freeze
      FALSY = %w[false 0 no off].freeze

      def self.cast(raw, _config = {})
        return raw if raw.is_a?(TrueClass) || raw.is_a?(FalseClass)

        str = raw.to_s.strip.downcase
        return true if TRUTHY.include?(str)
        return false if FALSY.include?(str)

        raw
      end

      def self.normalize(value, _config = {})
        value
      end

      def self.validate(value, _config = {})
        return [] if value.is_a?(TrueClass) || value.is_a?(FalseClass)
        ["must be a boolean"]
      end
    end
  end
end
