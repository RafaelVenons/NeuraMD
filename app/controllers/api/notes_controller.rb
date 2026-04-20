module Api
  class NotesController < BaseController
    def show
      note = resolve_note(params[:slug])
      return render_not_found unless note

      authorize note, :show?
      revision = readable_current_revision(note)
      render json: show_payload(note, revision)
    end

    def draft
      note = resolve_note(params[:slug])
      return render_not_found unless note

      authorize note, :update?
      result = ::Notes::DraftService.call(
        note: note,
        content: params[:content_markdown].to_s,
        author: current_user
      )
      render json: {saved: true, kind: "draft", graph_changed: result.graph_changed}
    rescue => e
      render_error(status: :unprocessable_entity, code: "draft_failed", message: e.message)
    end

    private

    def show_payload(note, revision)
      {
        note: {
          id: note.id,
          slug: note.slug,
          title: note.title,
          detected_language: note.detected_language,
          head_revision_id: note.head_revision_id
        },
        revision: {
          id: revision&.id,
          kind: revision&.revision_kind,
          content_markdown: revision&.content_markdown.to_s,
          updated_at: revision&.updated_at&.iso8601
        },
        tags: note.tags.where(tag_scope: %w[note both]).order(:name).map { |t|
          {id: t.id, name: t.name, color_hex: t.color_hex}
        },
        aliases: note.note_aliases.order(:name).pluck(:name),
        properties: (revision&.properties_data || {}).except("_errors"),
        properties_errors: (revision&.properties_data || {}).dig("_errors") || {}
      }
    end

    def resolve_note(slug)
      note = Note.active.find_by(slug: slug) || Note.active.find_by(id: slug)
      return note if note

      redirect_record = SlugRedirect.includes(:note).find_by(slug: slug)
      return redirect_record.note if redirect_record&.note && !redirect_record.note.deleted?

      alias_record = NoteAlias.includes(:note).where("lower(name) = lower(?)", slug).first
      return alias_record.note if alias_record&.note && !alias_record.note.deleted?

      nil
    end

    def readable_current_revision(note)
      candidates = []
      draft = note.note_revisions.find_by(revision_kind: :draft)
      candidates << draft if draft.present?
      candidates << note.head_revision if note.head_revision.present?

      remaining_checkpoints = note.note_revisions
        .where(revision_kind: :checkpoint)
        .where.not(id: candidates.compact.map(&:id))
        .order(created_at: :desc)
      remaining_checkpoints.find_each { |rev| candidates << rev }

      candidates.compact.find { |rev| readable_revision?(rev) }
    end

    def readable_revision?(revision)
      revision.content_markdown
      true
    rescue ActiveRecord::Encryption::Errors::Decryption => e
      Rails.logger.warn("[Api::NotesController] unreadable revision #{revision.id} for note #{revision.note_id}: #{e.class}")
      false
    end
  end
end
