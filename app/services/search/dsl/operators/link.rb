module Search
  module Dsl
    module Operators
      module Link
        def self.apply(scope, value)
          target_ids = Note.active.where("title ILIKE ?", value).select(:id)
          scope.where(
            id: NoteLink.active.where(dst_note_id: target_ids).select(:src_note_id)
          )
        end
      end
    end
  end
end
