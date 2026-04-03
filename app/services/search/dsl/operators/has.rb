module Search
  module Dsl
    module Operators
      module Has
        def self.apply(scope, value)
          return scope unless value.downcase == "asset"

          revision_ids = ActiveStorage::Attachment
            .where(record_type: "NoteRevision", name: "assets")
            .select(:record_id)

          scope.where(head_revision_id: revision_ids)
        end

        def self.validate(value)
          "valor desconhecido: #{value}" unless value.downcase == "asset"
        end
      end
    end
  end
end
