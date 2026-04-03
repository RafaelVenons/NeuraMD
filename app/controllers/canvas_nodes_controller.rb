class CanvasNodesController < ApplicationController
  before_action :set_canvas_document
  before_action :set_canvas_node, only: [:update, :destroy]

  def create
    authorize @canvas_document, :update?
    node = @canvas_document.canvas_nodes.build(node_params)

    if node.save
      render json: node_json(node), status: :created
    else
      render json: {errors: node.errors.full_messages}, status: :unprocessable_entity
    end
  end

  def update
    authorize @canvas_document, :update?

    if @canvas_node.update(node_params)
      render json: node_json(@canvas_node)
    else
      render json: {errors: @canvas_node.errors.full_messages}, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @canvas_document, :update?
    @canvas_node.destroy!
    head :no_content
  end

  def bulk_update
    authorize @canvas_document, :update?

    updates = params.require(:nodes)
    CanvasNode.transaction do
      updates.each do |u|
        permitted = u.permit(:id, :x, :y, :width, :height)
        @canvas_document.canvas_nodes.find(permitted[:id]).update!(permitted.except(:id).to_h)
      end
    end

    head :no_content
  end

  private

  def set_canvas_document
    @canvas_document = CanvasDocument.find(params[:canvas_document_id])
  end

  def set_canvas_node
    @canvas_node = @canvas_document.canvas_nodes.find(params[:id])
  end

  def node_params
    permitted = params.require(:canvas_node).permit(:node_type, :note_id, :x, :y, :width, :height, :z_index)
    if params.dig(:canvas_node, :data).present?
      raw = params.dig(:canvas_node, :data)
      permitted[:data] = raw.is_a?(String) ? JSON.parse(raw) : raw.to_unsafe_h
    end
    permitted
  rescue JSON::ParserError
    permitted
  end

  def node_json(node)
    json = {
      id: node.id,
      node_type: node.node_type,
      note_id: node.note_id,
      x: node.x,
      y: node.y,
      width: node.width,
      height: node.height,
      data: node.data,
      z_index: node.z_index
    }
    if node.note
      json[:title] = node.note.title
      json[:slug] = node.note.slug
    end
    json
  end
end
