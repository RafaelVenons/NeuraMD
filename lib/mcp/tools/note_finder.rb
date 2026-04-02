# frozen_string_literal: true

module Mcp
  module Tools
    module NoteFinder
      def find_note(slug)
        note = Note.active.find_by(slug: slug)
        return note if note

        redirect = SlugRedirect.includes(:note).find_by(slug: slug)
        return redirect.note if redirect&.note && !redirect.note.deleted?

        alias_record = NoteAlias.includes(:note).where("lower(name) = lower(?)", slug).first
        return alias_record.note if alias_record&.note && !alias_record.note.deleted?

        nil
      end
    end
  end
end
