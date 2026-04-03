module Search
  module Dsl
    module Operators
      module LinkedFrom
        def self.apply(scope, value)
          source_ids = Note.active.where("title ILIKE ?", value).select(:id)
          scope.where(
            id: NoteLink.active.where(src_note_id: source_ids).select(:dst_note_id)
          )
        end
      end
    end
  end
end
