class CanvasEdgesController < ApplicationController
  before_action :set_canvas_document
  before_action :set_canvas_edge, only: [:update, :destroy]

  def create
    authorize @canvas_document, :update?
    edge = @canvas_document.canvas_edges.build(edge_params)

    if edge.save
      render json: edge_json(edge), status: :created
    else
      render json: {errors: edge.errors.full_messages}, status: :unprocessable_entity
    end
  end

  def update
    authorize @canvas_document, :update?

    if @canvas_edge.update(edge_params)
      render json: edge_json(@canvas_edge)
    else
      render json: {errors: @canvas_edge.errors.full_messages}, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @canvas_document, :update?
    @canvas_edge.destroy!
    head :no_content
  end

  private

  def set_canvas_document
    @canvas_document = CanvasDocument.find(params[:canvas_document_id])
  end

  def set_canvas_edge
    @canvas_edge = @canvas_document.canvas_edges.find(params[:id])
  end

  def edge_params
    permitted = params.require(:canvas_edge).permit(:source_node_id, :target_node_id, :edge_type, :label)
    if params.dig(:canvas_edge, :style).present?
      raw = params.dig(:canvas_edge, :style)
      permitted[:style] = raw.is_a?(String) ? JSON.parse(raw) : raw.to_unsafe_h
    end
    permitted
  rescue JSON::ParserError
    permitted
  end

  def edge_json(edge)
    {
      id: edge.id,
      source_node_id: edge.source_node_id,
      target_node_id: edge.target_node_id,
      edge_type: edge.edge_type,
      label: edge.label,
      style: edge.style
    }
  end
end
