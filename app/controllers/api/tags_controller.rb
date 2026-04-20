module Api
  class TagsController < BaseController
    def index
      tags = Tag.where(tag_scope: %w[note both]).order(:name).map { |t|
        {id: t.id, name: t.name, color_hex: t.color_hex}
      }
      render json: {tags: tags}
    end
  end
end
