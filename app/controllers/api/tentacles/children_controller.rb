module Api
  module Tentacles
    class ChildrenController < Api::BaseController
      before_action :ensure_tentacles_enabled!
      before_action :set_parent

      def create
        authorize @parent, :update?
        title = params[:title].to_s
        description = params[:description]
        extra_tags  = params[:extra_tags]

        result = ::Tentacles::ChildSpawner.call(
          parent: @parent, title: title, description: description, extra_tags: extra_tags
        )
        child = result.child

        render json: {
          spawned: true,
          id: child.id,
          slug: child.slug,
          title: child.title,
          parent_slug: @parent.slug,
          tags: child.tags.pluck(:name),
          tentacle_url: "/app/notes/#{child.slug}/tentacle"
        }, status: :created
      rescue ::Tentacles::ChildSpawner::BlankTitle => e
        render_error(status: :unprocessable_entity, code: "invalid_params", message: e.message)
      end

      private

      def ensure_tentacles_enabled!
        return if ::Tentacles::Authorization.enabled?

        render_forbidden
      end

      def set_parent
        @parent = Note.active.find_by(slug: params[:slug])
        render_not_found unless @parent
      end
    end
  end
end
