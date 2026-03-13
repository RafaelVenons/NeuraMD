class TagsController < ApplicationController
  def index
    tags = Tag.order(:name).map do |t|
      { id: t.id, name: t.name, color_hex: t.color_hex || "#3b82f6", tag_scope: t.tag_scope }
    end
    render json: tags
  end

  def create
    tag = Tag.new(tag_params)
    if tag.save
      render json: { id: tag.id, name: tag.name, color_hex: tag.color_hex || "#3b82f6", tag_scope: tag.tag_scope },
             status: :created
    else
      render json: { errors: tag.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    tag = Tag.find(params[:id])
    tag.destroy
    head :no_content
  end

  private

  def tag_params
    params.require(:tag).permit(:name, :color_hex, :tag_scope)
  end
end
