module Search
  module Dsl
    module Operators
      module Tag
        def self.apply(scope, value)
          scope.where(
            id: NoteTag.joins(:tag).where(tags: {name: value.downcase}).select(:note_id)
          )
        end
      end
    end
  end
end
