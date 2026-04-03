module Search
  module Dsl
    module Operators
      module Prop
        def self.apply(scope, value)
          key, val = value.split("=", 2)
          return scope unless key.present? && val.present?

          scope.where("search_revisions.properties_data @> ?", {key => val}.to_json)
        end

        def self.validate(value)
          "deve conter = (ex: prop:status=done)" unless value.include?("=")
        end
      end
    end
  end
end
