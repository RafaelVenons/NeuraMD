module Search
  module Dsl
    class Parser
      OPERATORS = %w[tag alias prop kind status has link linkedfrom orphan deadend created updated].freeze
      OPERATOR_PATTERN = /\b(#{OPERATORS.join('|')}):(\S+)/i

      Result = Data.define(:tokens, :text, :errors)

      def self.call(query)
        new(query).call
      end

      def initialize(query)
        @query = query.to_s.strip
      end

      def call
        tokens = []
        errors = []
        remaining = @query.dup

        @query.scan(OPERATOR_PATTERN) do
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

      def validate(operator, value)
        case operator
        when :orphan, :deadend
          "deve ser true ou false" unless %w[true false].include?(value.downcase)
        when :has
          "valor desconhecido: #{value}" unless value.downcase == "asset"
        when :created, :updated
          "formato de data invalido: #{value}" unless DateParser.call(value)
        when :prop
          "deve conter = (ex: prop:status=done)" unless value.include?("=")
        end
      end
    end
  end
end
