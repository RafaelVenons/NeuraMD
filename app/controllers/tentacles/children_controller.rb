module Tentacles
  class ChildrenController < ApplicationController
    before_action :ensure_tentacles_enabled!
    before_action :set_parent

    def create
      authorize @parent, :update?
      title = params[:title].to_s
      description = params[:description]
      extra_tags  = params[:extra_tags]

      result = Tentacles::ChildSpawner.call(
        parent: @parent, title: title, description: description, extra_tags: extra_tags
      )
      child = result.child

      respond_to do |format|
        format.html { redirect_to note_tentacle_path(child.slug) }
        format.json { render json: payload(child), status: :created }
      end
    rescue Tentacles::ChildSpawner::BlankTitle => e
      respond_to do |format|
        format.html { redirect_to note_tentacle_path(@parent.slug), alert: e.message }
        format.json { render json: {error: e.message}, status: :unprocessable_entity }
      end
    end

    private

    def ensure_tentacles_enabled!
      return if Tentacles::Authorization.enabled?

      respond_to do |format|
        format.html { redirect_to root_path, alert: "Tentacles disabled in this environment." }
        format.json { render json: {error: "Tentacles disabled in this environment."}, status: :forbidden }
      end
    end

    def set_parent
      @parent = Note.active.find_by(slug: params[:note_slug])
      return if @parent

      respond_to do |format|
        format.html { redirect_to root_path, alert: "Parent note not found." }
        format.json { render json: {error: "Parent note not found."}, status: :not_found }
      end
    end

    def payload(child)
      {
        spawned: true,
        slug: child.slug,
        id: child.id,
        title: child.title,
        parent_slug: @parent.slug,
        tags: child.tags.pluck(:name),
        tentacle_url: note_tentacle_path(child.slug)
      }
    end
  end
end
