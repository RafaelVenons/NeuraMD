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

    def update_properties
      note = resolve_note(params[:slug])
      return render_not_found unless note

      authorize note, :update?
      raw = params[:changes]
      changes = raw.is_a?(ActionController::Parameters) ? raw.permit!.to_h : raw.to_h
      revision = ::Properties::SetService.call(
        note: note,
        changes: changes,
        author: current_user,
        strict: false
      )
      note.reload
      render json: {
        properties: (revision.properties_data || {}).except("_errors"),
        properties_errors: (revision.properties_data || {}).dig("_errors") || {}
      }
    rescue ::Properties::SetService::UnknownKeyError => e
      render_error(status: :unprocessable_entity, code: "unknown_property_key", message: e.message)
    rescue => e
      render_error(status: :unprocessable_entity, code: "properties_failed", message: e.message)
    end

    def attach_tag
      note = resolve_note(params[:slug])
      return render_not_found unless note

      authorize note, :update?
      name = params[:name].to_s.strip
      return render_error(status: :unprocessable_entity, code: "invalid_params", message: "Tag name is required.") if name.blank?

      color = params[:color_hex].presence
      tag = Tag.find_by("lower(name) = ?", name.downcase)
      if tag.nil?
        tag = Tag.new(name: name, tag_scope: "note", color_hex: color)
        unless tag.save
          return render_error(status: :unprocessable_entity, code: "invalid_params", message: tag.errors.full_messages.to_sentence)
        end
      elsif tag.tag_scope == "link"
        tag.update!(tag_scope: "both")
      end

      NoteTag.find_or_create_by!(note: note, tag: tag)
      render json: {tags: tag_list(note)}
    end

    def detach_tag
      note = resolve_note(params[:slug])
      return render_not_found unless note

      authorize note, :update?
      tag = Tag.find_by(id: params[:tag_id])
      return render_not_found unless tag

      NoteTag.where(note: note, tag: tag).delete_all
      render json: {tags: tag_list(note)}
    end

    def checkpoint
      note = resolve_note(params[:slug])
      return render_not_found unless note

      authorize note, :update?
      result = ::Notes::CheckpointService.call(
        note: note,
        content: params[:content_markdown].to_s,
        author: current_user
      )
      revision = result.revision
      render json: {
        saved: true,
        kind: "checkpoint",
        revision_id: revision.id,
        created_at: revision.created_at.iso8601,
        graph_changed: result.graph_changed
      }
    rescue => e
      render_error(status: :unprocessable_entity, code: "checkpoint_failed", message: e.message)
    end

    def revisions
      note = resolve_note(params[:slug])
      return render_not_found unless note

      authorize note, :show?
      entries = note.note_revisions
        .where(revision_kind: :checkpoint)
        .order(created_at: :desc)
        .map { |r|
          {
            id: r.id,
            created_at: r.created_at.iso8601,
            ai_generated: r.ai_generated,
            is_head: r.id == note.head_revision_id
          }
        }
      render json: {revisions: entries}
    end

    def restore_revision
      note = resolve_note(params[:slug])
      return render_not_found unless note

      authorize note, :update?
      source = note.note_revisions.where(revision_kind: :checkpoint).find_by(id: params[:revision_id])
      return render_not_found unless source

      result = ::Notes::CheckpointService.call(
        note: note,
        content: source.content_markdown,
        author: current_user,
        properties_data: source.properties_data
      )
      render json: {
        saved: true,
        revision_id: result.revision.id,
        graph_changed: result.graph_changed
      }
    rescue => e
      render_error(status: :unprocessable_entity, code: "restore_failed", message: e.message)
    end

    def links
      note = resolve_note(params[:slug])
      return render_not_found unless note

      authorize note, :show?
      outgoing = note.active_outgoing_links
        .includes(:dst_note)
        .to_a
        .select { |l| l.dst_note && !l.dst_note.deleted? }
        .map { |l| serialize_link(l.dst_note, l.hier_role) }
      incoming = note.active_incoming_links
        .includes(:src_note)
        .to_a
        .select { |l| l.src_note && !l.src_note.deleted? }
        .map { |l| serialize_link(l.src_note, l.hier_role) }

      render json: {outgoing: outgoing, incoming: incoming}
    end

    def ai_requests
      note = resolve_note(params[:slug])
      return render_not_found unless note

      authorize note, :show?
      requests = ::AiRequest
        .joins(:note_revision)
        .where(note_revisions: {note_id: note.id})
        .recent_first
        .limit(20)
      render json: {requests: requests.map { |r| serialize_ai_request(r) }}
    end

    def tts
      note = resolve_note(params[:slug])
      return render_not_found unless note

      authorize note, :show?
      active = ::NoteTtsAsset.for_note(note).ready.order(created_at: :desc).first
      library_count = ::NoteTtsAsset.for_note(note).count
      render json: {
        active_asset: active ? serialize_tts_asset(active) : nil,
        library_count: library_count
      }
    end

    private

    def serialize_ai_request(request)
      {
        id: request.id,
        capability: request.capability,
        provider: request.provider,
        status: request.status,
        attempts_count: request.attempts_count,
        max_attempts: request.max_attempts,
        last_error_kind: request.last_error_kind,
        error_message: request.error_message,
        created_at: request.created_at.iso8601
      }
    end

    def serialize_tts_asset(asset)
      {
        id: asset.id,
        revision_id: asset.note_revision_id,
        language: asset.language,
        voice: asset.voice,
        provider: asset.provider,
        format: asset.format,
        duration_ms: asset.duration_ms,
        audio_url: asset.audio.attached? ? rails_blob_url(asset.audio, disposition: :inline) : nil,
        created_at: asset.created_at&.iso8601
      }
    end

    def serialize_link(note, hier_role)
      {
        id: note.id,
        slug: note.slug,
        title: note.title,
        hier_role: hier_role
      }
    end

    def tag_list(note)
      note.tags.where(tag_scope: %w[note both]).order(:name).map { |t|
        {id: t.id, name: t.name, color_hex: t.color_hex}
      }
    end

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
        properties_errors: (revision&.properties_data || {}).dig("_errors") || {},
        property_definitions: PropertyDefinition.active.order(:position, :key).map { |d|
          {
            key: d.key,
            value_type: d.value_type,
            label: d.label,
            description: d.description,
            config: d.config
          }
        }
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
      if draft.present? && draft_fresh?(draft, note)
        candidates << draft
      end
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

    # A draft is "fresh" only when it was stamped against the note's current
    # head revision. A stale draft (base_revision_id != head_revision_id) was
    # created before a newer checkpoint landed — it must not shadow the head.
    def draft_fresh?(draft, note)
      return true if note.head_revision_id.blank?
      draft.base_revision_id == note.head_revision_id
    end
  end
end
