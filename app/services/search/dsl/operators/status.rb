module Search
  module Dsl
    module Operators
      module Status
        def self.apply(scope, value)
          Prop.apply(scope, "status=#{value}")
        end
      end
    end
  end
end
