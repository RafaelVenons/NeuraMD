module Search
  module Dsl
    module Operators
      module Kind
        def self.apply(scope, value)
          Prop.apply(scope, "kind=#{value}")
        end
      end
    end
  end
end
