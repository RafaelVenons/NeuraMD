module Search
  module Dsl
    class Executor
      def self.call(scope:, tokens:)
        tokens.reduce(scope) { |s, token| apply(s, token) }
      end

      class << self
        private

        def apply(scope, token)
          OperatorRegistry.invoke_safe(token.operator, scope, token.value) || scope
        end
      end
    end
  end
end
