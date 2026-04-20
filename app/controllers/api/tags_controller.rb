module Api
  class TagsController < BaseController
    def index
      scope = params[:scope] == "all" ? ::Tag.all : ::Tag.where(tag_scope: %w[note both])
      rows = scope
        .left_joins(:note_tags)
        .select("tags.*, COUNT(note_tags.note_id) AS notes_count")
        .group("tags.id")
        .order(:name)
      render json: {
        tags: rows.map { |t|
          {
            id: t.id,
            name: t.name,
            color_hex: t.color_hex,
            tag_scope: t.tag_scope,
            notes_count: t.notes_count.to_i
          }
        }
      }
    end
  end
end
