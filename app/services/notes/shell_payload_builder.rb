module Notes
  class ShellPayloadBuilder
    include Rails.application.routes.url_helpers

    def self.call(note:, revision:, controller:)
      new(note, revision, controller).build
    end

    def initialize(note, revision, controller)
      @note = note
      @revision = revision
      @controller = controller
    end

    def build
      {
        title: "#{@note.title} — NeuraMD",
        note: note_payload,
        revision: revision_payload,
        urls: urls_payload,
        ai: ai_payload,
        html: html_payload,
        link_tags_map: outgoing_link_tags_payload,
        note_tags: @note.tags.where(tag_scope: %w[note both]).map { |t| {id: t.id, name: t.name, color_hex: t.color_hex} },
        aliases: @note.note_aliases.pluck(:name),
        properties: (@revision&.properties_data || {}).except("_errors"),
        properties_errors: (@revision&.properties_data || {}).dig("_errors") || {},
        property_definitions: PropertyDefinition.active.order(:position, :key).map { |d|
          {key: d.key, value_type: d.value_type, label: d.label, description: d.description, config: d.config}
        }
      }
    end

    private

    def note_payload
      {
        id: @note.id,
        slug: @note.slug,
        title: @note.title,
        detected_language: @note.detected_language,
        head_revision_id: @note.head_revision_id
      }
    end

    def revision_payload
      {
        id: @revision&.id,
        kind: @revision&.revision_kind,
        content_markdown: @revision&.content_markdown.to_s,
        updated_at: @revision&.updated_at&.iso8601
      }
    end

    def urls_payload
      slug = @note.slug
      {
        draft: draft_note_path(slug),
        checkpoint: checkpoint_note_path(slug),
        revisions: revisions_note_path(slug),
        update: note_path(slug),
        show: note_path(slug),
        queue: ai_requests_dashboard_path(format: :json),
        queue_reorder: reorder_ai_requests_dashboard_path,
        queue_request_template: ai_request_payload_path("__REQUEST_ID__"),
        queue_retry_template: retry_ai_request_path("__REQUEST_ID__"),
        queue_cancel_template: ai_request_dashboard_path("__REQUEST_ID__"),
        queue_resolve_template: resolve_ai_request_queue_path("__REQUEST_ID__"),
        ai_status: ai_status_note_path(slug),
        ai_review: ai_review_note_path(slug),
        ai_history: ai_requests_note_path(slug),
        ai_reorder: reorder_ai_requests_note_path(slug),
        ai_request_template: ai_request_note_path(slug, "__REQUEST_ID__"),
        ai_retry_template: retry_ai_request_note_path(slug, "__REQUEST_ID__"),
        ai_cancel_template: ai_request_note_path(slug, "__REQUEST_ID__"),
        ai_resolve_template: resolve_ai_request_queue_note_path(slug, "__REQUEST_ID__"),
        ai_create_translated_note_template: ai_request_translated_note_note_path(slug, "__REQUEST_ID__"),
        wikilink_create_promise: create_from_promise_note_path(slug),
        link_info_template: "#{link_info_note_path(slug)}?dst_uuid=__DST_UUID__",
        properties: properties_note_path(slug),
        aliases: aliases_note_path(slug),
        convert_mention: convert_mention_note_path(slug),
        dismiss_mention: dismiss_mention_note_path(slug)
      }
    end

    def ai_payload
      {
        note_title: @note.title,
        note_language: @note.detected_language,
        language_options: Note::SUPPORTED_LANGUAGES.reject { |lang| lang == @note.detected_language },
        language_labels: Notes::TranslationNoteService::LANGUAGE_LABELS
      }
    end

    def html_payload
      {
        backlinks: @controller.render_to_string(partial: "notes/backlinks_content", formats: [:html], locals: {note: @note}),
        mentions: @controller.render_to_string(partial: "notes/mentions_content", formats: [:html],
          locals: {mentions: Mentions::UnlinkedService.call(note: @note).mentions}),
        ai_requests_stream: @controller.render_to_string(partial: "notes/ai_requests_stream", formats: [:html], locals: {note: @note})
      }
    end

    def outgoing_link_tags_payload
      @note.outgoing_links.includes(:tags).each_with_object({}) do |link, payload|
        payload[link.dst_note_id.to_s] = link.tags.map(&:id).map(&:to_s)
      end
    end
  end
end
