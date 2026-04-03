module Search
  module Dsl
    module Operators
      module Orphan
        def self.apply(scope, _value)
          scope
            .where.not(id: NoteLink.active.select(:src_note_id))
            .where.not(id: NoteLink.active.select(:dst_note_id))
        end

        def self.validate(value)
          "deve ser true ou false" unless %w[true false].include?(value.downcase)
        end
      end
    end
  end
end
