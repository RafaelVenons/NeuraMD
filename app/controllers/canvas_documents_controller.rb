class CanvasDocumentsController < ApplicationController
  before_action :set_canvas_document, only: [:show, :update, :destroy]

  def index
    authorize CanvasDocument
    @canvas_documents = CanvasDocument.ordered
  end

  def show
    authorize @canvas_document
    nodes = @canvas_document.canvas_nodes.includes(:note)
    @nodes_json = nodes.map { |n| node_json(n) }.to_json
    @edges_json = @canvas_document.canvas_edges.map { |e| edge_json(e) }.to_json
  end

  def create
    @canvas_document = CanvasDocument.new(document_params)
    authorize @canvas_document

    if @canvas_document.save
      render json: document_json(@canvas_document), status: :created
    else
      render json: {errors: @canvas_document.errors.full_messages}, status: :unprocessable_entity
    end
  end

  def update
    authorize @canvas_document

    if @canvas_document.update(document_params)
      render json: document_json(@canvas_document)
    else
      render json: {errors: @canvas_document.errors.full_messages}, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @canvas_document
    @canvas_document.destroy!
    head :no_content
  end

  private

  def set_canvas_document
    @canvas_document = CanvasDocument.find(params[:id])
  end

  def document_params
    permitted = params.require(:canvas_document).permit(:name, :position)
    if params.dig(:canvas_document, :viewport).present?
      raw = params.dig(:canvas_document, :viewport)
      permitted[:viewport] = raw.is_a?(String) ? JSON.parse(raw) : raw.to_unsafe_h
    end
    permitted
  rescue JSON::ParserError
    permitted
  end

  def document_json(doc)
    {
      id: doc.id,
      name: doc.name,
      viewport: doc.viewport,
      position: doc.position,
      node_count: doc.canvas_nodes.count,
      created_at: doc.created_at.iso8601,
      updated_at: doc.updated_at.iso8601
    }
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
      json[:excerpt] = node.note.head_revision&.content_plain.to_s.truncate(200)
    end
    json
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
