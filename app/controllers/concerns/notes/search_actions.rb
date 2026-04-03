module Notes
  module SearchActions
    extend ActiveSupport::Concern

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
          payload = {
            results: result.notes.map { |note| finder_payload(note) },
            meta: finder_meta(result)
          }
          payload[:dsl_errors] = result.dsl_errors if result.dsl_errors&.any?
          render json: payload
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

    def search_suggestions
      authorize Note.new, :index?
      suggestions = case params[:operator]
      when "tag"    then Tag.order(:name).limit(30).pluck(:name)
      when "kind"   then PropertyDefinition.find_by(key: "kind")&.config&.dig("options") || []
      when "status" then PropertyDefinition.find_by(key: "status")&.config&.dig("options") || []
      when "prop"   then PropertyDefinition.active.order(:position).pluck(:key)
      else []
      end
      render json: {suggestions: suggestions}
    end

    private

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
  end
end
