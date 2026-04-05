module Search
  module Dsl
    module Operators
      module DateFilter
        ALLOWED_COLUMNS = %w[notes.created_at notes.updated_at].freeze

        def self.apply(scope, column, value)
          raise ArgumentError, "Invalid column: #{column}" unless ALLOWED_COLUMNS.include?(column)

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
