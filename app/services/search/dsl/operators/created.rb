module Search
  module Dsl
    module Operators
      module Created
        def self.apply(scope, value)
          DateFilter.apply(scope, "notes.created_at", value)
        end

        def self.validate(value)
          "formato de data invalido: #{value}" unless DateParser.call(value)
        end
      end
    end
  end
end
