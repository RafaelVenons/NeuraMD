module Api
  class PropertyDefinitionsController < Api::BaseController
    before_action :set_definition, only: [:update, :destroy]

    def index
      authorize ::PropertyDefinition
      definitions = ::PropertyDefinition.active.order(:position, :key)
      render json: {definitions: definitions.map { |d| serialize(d) }}
    end

    def create
      definition = ::PropertyDefinition.new(create_params)
      authorize definition

      if definition.save
        render json: {definition: serialize(definition)}, status: :created
      else
        render_error(message: definition.errors.full_messages.to_sentence, status: :unprocessable_entity,
          code: "invalid_params", details: definition.errors.messages)
      end
    end

    def update
      authorize @definition

      if @definition.update(update_params)
        render json: {definition: serialize(@definition)}
      else
        render_error(message: @definition.errors.full_messages.to_sentence, status: :unprocessable_entity,
          code: "invalid_params", details: @definition.errors.messages)
      end
    end

    def destroy
      authorize @definition
      @definition.update!(archived: true)
      head :no_content
    end

    def reorder
      authorize ::PropertyDefinition
      ids = params.require(:ids)
      ids.each_with_index do |id, index|
        ::PropertyDefinition.where(id: id).update_all(position: index)
      end
      head :no_content
    end

    private

    def set_definition
      @definition = ::PropertyDefinition.find(params[:id])
    end

    def create_params
      permitted = params.require(:property_definition).permit(:key, :value_type, :label, :description)
      permitted[:config] = parse_config
      permitted[:position] = ::PropertyDefinition.maximum(:position).to_i + 1
      permitted
    end

    def update_params
      permitted = params.require(:property_definition).permit(:label, :description)
      permitted[:config] = parse_config if params[:property_definition].key?(:config)
      permitted
    end

    def parse_config
      raw = params.dig(:property_definition, :config)
      return {} if raw.blank?
      raw.is_a?(String) ? JSON.parse(raw) : raw.to_unsafe_h
    rescue JSON::ParserError
      {}
    end

    def serialize(definition)
      {
        id: definition.id,
        key: definition.key,
        value_type: definition.value_type,
        label: definition.label,
        description: definition.description,
        config: definition.config,
        system: definition.system,
        archived: definition.archived,
        position: definition.position
      }
    end
  end
end
