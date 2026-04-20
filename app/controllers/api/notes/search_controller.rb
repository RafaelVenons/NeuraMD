module Api
  module Notes
    class SearchController < Api::BaseController
      MAX_LIMIT = 25

      def index
        limit = sanitize_limit(params[:limit])
        page = [params[:page].to_i, 1].max

        result = ::Search::NoteQueryService.call(
          scope: policy_scope(::Note),
          query: params[:q],
          regex: false,
          page: page,
          limit: limit
        )

        render json: {
          results: result.notes.map { |note| serialize(note) },
          meta: {
            query: result.query,
            page: result.page,
            limit: result.limit,
            has_more: result.has_more
          }
        }
      end

      private

      def sanitize_limit(raw)
        value = raw.to_i
        return ::Search::NoteQueryService::DEFAULT_LIMIT if value <= 0
        [value, MAX_LIMIT].min
      end

      def serialize(note)
        {
          id: note.id,
          slug: note.slug,
          title: note.title,
          snippet: snippet_for(note),
          updated_at: note.updated_at.iso8601
        }
      end

      def snippet_for(note)
        revision = note.head_revision
        return "" if revision.blank?

        if note.attributes["search_content_plain"].present?
          revision = revision.dup
          revision.content_plain = note.attributes["search_content_plain"]
        end

        revision.search_preview_text(limit: 180).to_s
      end
    end
  end
end
