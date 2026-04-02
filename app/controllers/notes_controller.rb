class NotesController < ApplicationController
  include ::DomainEvents
  before_action :set_note, only: [:show, :edit, :update, :destroy, :autosave, :draft, :checkpoint, :revisions, :show_revision, :restore_revision, :link_info, :create_from_promise, :convert_mention, :dismiss_mention]
  layout "editor", only: [:show, :show_revision]

  def index
    authorize Note.new, :index?
    redirect_to graph_path
  end

  def new
    @note = Note.new
    authorize @note
  end

  def create
    @note = Note.new(note_params)
    authorize @note

    if @note.save
      publish_event("note.created", note_id: @note.id, slug: @note.slug, title: @note.title)
      redirect_to note_path(@note.slug, focus: "title"), notice: "Nota criada."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    authorize @note
    # UUID-based URLs (from client-side wiki-link preview) → redirect to slug URL
    if params[:slug] != @note.slug
      if request.format.json?
        @revision = readable_current_revision(@note)
        return render json: note_shell_payload(@note, @revision)
      end

      redirect_to note_path(@note.slug), status: :moved_permanently and return
    end
    # Load draft for crash recovery if one exists; otherwise use head checkpoint
    @revision = readable_current_revision(@note)
    respond_to do |format|
      format.html
      format.json { render json: note_shell_payload(@note, @revision) }
    end
  end

  def edit
    authorize @note
  end

  def update
    authorize @note
    new_title = note_params[:title]
    title_changed = new_title.present? && new_title != @note.title

    if title_changed
      result = Notes::RenameService.call(note: @note, new_title: new_title)
      remaining = note_params.except(:title)
      @note.update!(remaining) if remaining.keys.any?
      redirect_to note_path(result.new_slug), notice: "Nota atualizada."
    elsif @note.update(note_params)
      redirect_to note_path(@note.slug), notice: "Nota atualizada."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @note
    @note.soft_delete!
    redirect_to graph_path, notice: "Nota arquivada."
  end

  def restore
    @note = Note.deleted.find_by!(slug: params[:slug])
    authorize @note, :update?
    @note.restore!
    redirect_to note_path(@note.slug), notice: "Nota restaurada."
  end

  def search
    authorize Note.new, :index?
    if params[:mode] == "resolve"
      result = Links::ResolveService.call(
        title: params[:q].to_s,
        exclude_id: params[:exclude_id]
      )
      render json: {
        status: result.status,
        match_kind: result.match_kind,
        notes: result.notes.map { |n| {id: n.id, title: n.title, slug: n.slug} }
      }
    elsif params[:mode] == "headings"
      note = Note.active.find(params[:note_id])
      authorize note, :show?
      headings = note.note_headings.order(:position)
      headings = headings.where("text ILIKE ?", "%#{Note.sanitize_sql_like(params[:q].to_s)}%") if params[:q].present?
      render json: headings.map { |h|
        {text: h.text, slug: h.slug, level: h.level, position: h.position}
      }
    elsif params[:mode] == "blocks"
      note = Note.active.find(params[:note_id])
      authorize note, :show?
      blocks = note.note_blocks.order(:position)
      blocks = blocks.where("content ILIKE ?", "%#{Note.sanitize_sql_like(params[:q].to_s)}%") if params[:q].present?
      render json: blocks.map { |b|
        {block_id: b.block_id, content: b.content, block_type: b.block_type, position: b.position}
      }
    elsif params[:mode] == "finder"
      result = Search::NoteQueryService.call(
        scope: policy_scope(Note),
        query: params[:q],
        regex: params[:regex],
        page: params[:page],
        limit: params[:limit] || 8
      )

      if result.error.present?
        render json: {results: [], error: result.error, meta: finder_meta(result)}, status: :unprocessable_entity
      else
        render json: {
          results: result.notes.map { |note| finder_payload(note) },
          meta: finder_meta(result)
        }
      end
    else
      notes = Note.search_by_title(params[:q].to_s, exclude_id: params[:exclude_id])
      render json: notes.map { |n|
        payload = {id: n.id, title: n.title, slug: n.slug}
        payload[:matched_alias] = n.matched_alias if n.respond_to?(:matched_alias) && n.matched_alias.present?
        payload
      }
    end
  end

  def autosave
    # Legacy endpoint — now delegates to draft behaviour
    draft
  end

  def draft
    authorize @note, :update?
    result = Notes::DraftService.call(note: @note, content: params[:content_markdown].to_s, author: current_user)
    render json: {saved: true, kind: "draft", graph_changed: result.graph_changed}
  rescue => e
    render json: {error: e.message}, status: :unprocessable_entity
  end

  def checkpoint
    authorize @note, :update?
    result = Notes::CheckpointService.call(
      note: @note,
      content: params[:content_markdown].to_s,
      author: current_user,
      accepted_ai_request: accepted_ai_request_for_checkpoint
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
    render json: {error: e.message}, status: :unprocessable_entity
  end

  def revisions
    authorize @note, :show?
    checkpoints = @note.note_revisions.where(revision_kind: :checkpoint).order(created_at: :asc).to_a

    entries = checkpoints.each_with_index.map { |r, i|
      prev_props = i > 0 ? (checkpoints[i - 1].properties_data || {}).except("_errors") : {}
      curr_props = (r.properties_data || {}).except("_errors")

      {
        id: r.id,
        ai_generated: r.ai_generated,
        created_at: r.created_at.iso8601,
        is_head: r.id == @note.head_revision_id,
        content_markdown: r.content_markdown,
        properties_data: curr_props,
        properties_diff: compute_properties_diff(prev_props, curr_props)
      }
    }

    render json: entries.reverse
  end

  def show_revision
    authorize @note, :show?
    @revision = @note.note_revisions.where(revision_kind: :checkpoint).find(params[:revision_id])
    render :show
  end

  def link_info
    authorize @note, :show?
    link = @note.outgoing_links.includes(:tags).find_by(dst_note_id: params[:dst_uuid])
    if link
      render json: {
        link_id: link.id,
        tags: link.tags.map { |t| {id: t.id, name: t.name, color_hex: t.color_hex || "#3b82f6"} }
      }
    else
      render json: {link_id: nil, tags: []}
    end
  end

  def restore_revision
    authorize @note, :update?
    source = @note.note_revisions.where(revision_kind: :checkpoint).find(params[:revision_id])
    result = Notes::CheckpointService.call(
      note: @note,
      content: source.content_markdown,
      author: current_user,
      properties_data: source.properties_data
    )
    render json: {saved: true, revision_id: result.revision.id, graph_changed: result.graph_changed}
  rescue => e
    render json: {error: e.message}, status: :unprocessable_entity
  end

  def create_from_promise
    authorize @note, :update?
    authorize Note.new, :create?

    promise_result = Notes::PromiseCreationService.call(
      source_note: @note,
      title: params[:title],
      author: current_user,
      mode: params[:mode]
    )
    promise_note = promise_result.note

    render json: {
      note_id: promise_note.id,
      note_slug: promise_note.slug,
      note_title: promise_note.title,
      note_url: note_path(promise_note.slug),
      created: promise_result.created,
      seeded: promise_result.seeded,
      request_id: promise_result.request&.id,
      request_status: promise_result.request&.status
    }, status: :created
  rescue Ai::Error, ArgumentError => e
    render json: {error: e.message}, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error("[NotesController#create_from_promise] #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace.present?
    render json: {error: "Falha interna ao criar nota com IA."}, status: :internal_server_error
  end

  def convert_mention
    authorize @note, :show?
    source_note = Note.active.find_by!(slug: params[:source_slug])
    authorize source_note, :update?

    result = Mentions::LinkService.call(
      source_note: source_note,
      target_note: @note,
      matched_term: params[:matched_term],
      author: current_user
    )

    mentions_result = Mentions::UnlinkedService.call(note: @note)
    render json: {
      linked: true,
      graph_changed: result.graph_changed,
      mentions_html: render_to_string(partial: "notes/mentions_content", formats: [:html],
        locals: {mentions: mentions_result.mentions})
    }
  end

  def dismiss_mention
    authorize @note, :show?
    source_note = Note.active.find_by!(slug: params[:source_slug])

    MentionExclusion.find_or_create_by!(
      note: @note,
      source_note: source_note,
      matched_term: params[:matched_term]
    )

    mentions_result = Mentions::UnlinkedService.call(note: @note)
    render json: {
      dismissed: true,
      mentions_html: render_to_string(partial: "notes/mentions_content", formats: [:html],
        locals: {mentions: mentions_result.mentions})
    }
  end

  private

  def compute_properties_diff(old_props, new_props)
    all_keys = (old_props.keys + new_props.keys).uniq
    diff = {"added" => {}, "removed" => {}, "changed" => {}}

    all_keys.each do |key|
      if !old_props.key?(key)
        diff["added"][key] = new_props[key]
      elsif !new_props.key?(key)
        diff["removed"][key] = old_props[key]
      elsif old_props[key] != new_props[key]
        diff["changed"][key] = {"from" => old_props[key], "to" => new_props[key]}
      end
    end

    diff
  end

  def accepted_ai_request_for_checkpoint
    return nil if params[:ai_request_id].blank?

    AiRequest.joins(note_revision: :note)
      .where(id: params[:ai_request_id], notes: {id: @note.id})
      .first!
  end

  def set_note
    @note = Note.active.find_by(slug: params[:slug]) ||
      Note.active.find_by(id: params[:slug])

    return if @note

    redirect_record = SlugRedirect.includes(:note).find_by(slug: params[:slug])
    if redirect_record&.note && !redirect_record.note.deleted?
      redirect_to note_path(redirect_record.note.slug), status: :moved_permanently
      return
    end

    alias_record = NoteAlias.includes(:note).where("lower(name) = lower(?)", params[:slug]).first
    if alias_record&.note && !alias_record.note.deleted?
      redirect_to note_path(alias_record.note.slug), status: :moved_permanently
      return
    end

    raise ActiveRecord::RecordNotFound
  end

  def note_params
    params.require(:note).permit(:title, :note_kind, :detected_language)
  end

  def finder_payload(note)
    {
      id: note.id,
      title: note.title,
      slug: note.slug,
      detected_language: note.detected_language,
      updated_at: note.updated_at.iso8601,
      snippet: finder_snippet(note)
    }
  end

  def finder_meta(result)
    {
      page: result.page,
      limit: result.limit,
      has_more: result.has_more,
      query: result.query,
      regex: result.regex
    }
  end

  def finder_snippet(note)
    revision = note.head_revision
    if revision.present? && note.attributes["search_content_plain"].present?
      revision = revision.dup
      revision.content_plain = note.attributes["search_content_plain"]
    end

    revision&.search_preview_text(limit: 180).to_s
  end

  def note_shell_payload(note, revision)
    {
      title: "#{note.title} — NeuraMD",
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
      urls: {
        draft: draft_note_path(note.slug),
        checkpoint: checkpoint_note_path(note.slug),
        revisions: revisions_note_path(note.slug),
        update: note_path(note.slug),
        show: note_path(note.slug),
        queue: ai_requests_dashboard_path(format: :json),
        queue_reorder: reorder_ai_requests_dashboard_path,
        queue_request_template: ai_request_payload_path("__REQUEST_ID__"),
        queue_retry_template: retry_ai_request_path("__REQUEST_ID__"),
        queue_cancel_template: ai_request_dashboard_path("__REQUEST_ID__"),
        queue_resolve_template: resolve_ai_request_queue_path("__REQUEST_ID__"),
        ai_status: ai_status_note_path(note.slug),
        ai_review: ai_review_note_path(note.slug),
        ai_history: ai_requests_note_path(note.slug),
        ai_reorder: reorder_ai_requests_note_path(note.slug),
        ai_request_template: ai_request_note_path(note.slug, "__REQUEST_ID__"),
        ai_retry_template: retry_ai_request_note_path(note.slug, "__REQUEST_ID__"),
        ai_cancel_template: ai_request_note_path(note.slug, "__REQUEST_ID__"),
        ai_resolve_template: resolve_ai_request_queue_note_path(note.slug, "__REQUEST_ID__"),
        ai_create_translated_note_template: ai_request_translated_note_note_path(note.slug, "__REQUEST_ID__"),
        wikilink_create_promise: create_from_promise_note_path(note.slug),
        link_info_template: "#{link_info_note_path(note.slug)}?dst_uuid=__DST_UUID__",
        properties: properties_note_path(note.slug),
        aliases: aliases_note_path(note.slug),
        convert_mention: convert_mention_note_path(note.slug),
        dismiss_mention: dismiss_mention_note_path(note.slug)
      },
      ai: {
        note_title: note.title,
        note_language: note.detected_language,
        language_options: Note::SUPPORTED_LANGUAGES.reject { |lang| lang == note.detected_language },
        language_labels: Notes::TranslationNoteService::LANGUAGE_LABELS
      },
      html: {
        backlinks: render_to_string(partial: "notes/backlinks_content", formats: [:html], locals: {note:}),
        mentions: render_to_string(partial: "notes/mentions_content", formats: [:html],
          locals: {mentions: Mentions::UnlinkedService.call(note: note).mentions}),
        ai_requests_stream: render_to_string(partial: "notes/ai_requests_stream", formats: [:html], locals: {note:})
      },
      link_tags_map: outgoing_link_tags_payload(note),
      note_tags: note.tags.where(tag_scope: %w[note both]).map { |t| { id: t.id, name: t.name, color_hex: t.color_hex } },
      aliases: note.note_aliases.pluck(:name),
      properties: (revision&.properties_data || {}).except("_errors"),
      properties_errors: (revision&.properties_data || {}).dig("_errors") || {},
      property_definitions: PropertyDefinition.active.order(:position, :key).map { |d|
        {key: d.key, value_type: d.value_type, label: d.label, description: d.description, config: d.config}
      }
    }
  end

  def outgoing_link_tags_payload(note)
    note.outgoing_links.includes(:tags).each_with_object({}) do |link, payload|
      payload[link.dst_note_id.to_s] = link.tags.map(&:id).map(&:to_s)
    end
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

    remaining_checkpoints.find_each do |revision|
      candidates << revision
    end

    candidates.compact.find do |revision|
      readable_revision?(revision)
    end
  end

  def readable_revision?(revision)
    revision.content_markdown
    true
  rescue ActiveRecord::Encryption::Errors::Decryption => e
    Rails.logger.warn("[NotesController] unreadable revision #{revision.id} for note #{revision.note_id}: #{e.class}")
    false
  end
end
