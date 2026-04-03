module Search
  module Dsl
    module Operators
      module DateFilter
        def self.apply(scope, column, value)
          parsed = DateParser.call(value)
          return scope unless parsed

          if parsed.comparator == :gt
            scope.where("#{column} > ?", parsed.timestamp)
          else
            scope.where("#{column} < ?", parsed.timestamp)
          end
        end
      end
    end
  end
end
