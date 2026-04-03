module Search
  module Dsl
    module Operators
      module AliasOp
        def self.apply(scope, value)
          scope.where(
            id: NoteAlias.where("note_aliases.name ILIKE ?", value).select(:note_id)
          )
        end
      end
    end
  end
end
