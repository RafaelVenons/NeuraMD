module Search
  module Dsl
    class Executor
      def self.call(scope:, tokens:)
        tokens.reduce(scope) { |s, token| apply(s, token) }
      end

      class << self
        private

        def apply(scope, token)
          case token.operator
          when :tag         then apply_tag(scope, token.value)
          when :alias       then apply_alias(scope, token.value)
          when :prop        then apply_prop(scope, token.value)
          when :kind        then apply_prop(scope, "kind=#{token.value}")
          when :status      then apply_prop(scope, "status=#{token.value}")
          when :has         then apply_has(scope, token.value)
          when :link        then apply_link(scope, token.value)
          when :linkedfrom  then apply_linkedfrom(scope, token.value)
          when :orphan      then apply_orphan(scope)
          when :deadend     then apply_deadend(scope)
          when :created     then apply_date(scope, "notes.created_at", token.value)
          when :updated     then apply_date(scope, "notes.updated_at", token.value)
          else scope
          end
        end

        def apply_tag(scope, value)
          scope.where(
            id: NoteTag.joins(:tag).where(tags: {name: value.downcase}).select(:note_id)
          )
        end

        def apply_alias(scope, value)
          scope.where(
            id: NoteAlias.where("note_aliases.name ILIKE ?", value).select(:note_id)
          )
        end

        def apply_prop(scope, expr)
          key, value = expr.split("=", 2)
          return scope unless key.present? && value.present?

          scope.where("search_revisions.properties_data @> ?", {key => value}.to_json)
        end

        def apply_has(scope, value)
          return scope unless value.downcase == "asset"

          revision_ids = ActiveStorage::Attachment
            .where(record_type: "NoteRevision", name: "assets")
            .select(:record_id)

          scope.where(head_revision_id: revision_ids)
        end

        def apply_link(scope, title)
          target_ids = Note.active.where("title ILIKE ?", title).select(:id)
          scope.where(
            id: NoteLink.active.where(dst_note_id: target_ids).select(:src_note_id)
          )
        end

        def apply_linkedfrom(scope, title)
          source_ids = Note.active.where("title ILIKE ?", title).select(:id)
          scope.where(
            id: NoteLink.active.where(src_note_id: source_ids).select(:dst_note_id)
          )
        end

        def apply_orphan(scope)
          scope
            .where.not(id: NoteLink.active.select(:src_note_id))
            .where.not(id: NoteLink.active.select(:dst_note_id))
        end

        def apply_deadend(scope)
          scope.where.not(id: NoteLink.active.select(:src_note_id))
        end

        def apply_date(scope, column, value)
          parsed = DateParser.call(value)
          return scope unless parsed

          if parsed.comparator == :gt
            scope.where("#{column} > ?", parsed.timestamp)
          else
            scope.where("#{column} < ?", parsed.timestamp)
          end
        end
      end
    end
  end
end
