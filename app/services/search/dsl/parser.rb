module Search
  module Dsl
    class Parser
      Result = Data.define(:tokens, :text, :errors)

      def self.call(query)
        new(query).call
      end

      def self.operators
        OperatorRegistry.names
      end

      def initialize(query)
        @query = query.to_s.strip
      end

      def call
        tokens = []
        errors = []
        remaining = @query.dup

        @query.scan(operator_pattern) do
          match = Regexp.last_match
          operator = match[1].downcase.to_sym
          value = match[2]
          raw = match[0]
          position = match.begin(0)

          error = validate(operator, value)
          if error
            errors << {operator: operator, value: value, message: error, position: position}
          else
            tokens << Token.new(operator: operator, value: value, raw: raw, position: position)
            remaining = remaining.sub(raw, " ")
          end
        end

        text = remaining.gsub(/\s+/, " ").strip

        Result.new(tokens: tokens, text: text, errors: errors)
      end

      private

      def operator_pattern
        ops = OperatorRegistry.names.join("|")
        /\b(#{ops}):(\S+)/i
      end

      def validate(operator, value)
        handler = OperatorRegistry.lookup_safe(operator)
        return unless handler&.respond_to?(:validate)
        handler.validate(value)
      end
    end
  end
end
