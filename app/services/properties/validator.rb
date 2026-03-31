module Properties
  class Validator
    Result = Struct.new(:valid, :errors, keyword_init: true) do
      alias_method :valid?, :valid
    end

    def self.call(properties_data)
      new(properties_data).call
    end

    def initialize(properties_data)
      @properties_data = (properties_data || {}).except("_errors")
    end

    def call
      registry = PropertyDefinition.registry
      errors = {}

      @properties_data.each do |key, value|
        definition = registry[key]
        unless definition
          errors[key] = ["unknown property key"]
          next
        end

        type_errors = TypeRegistry.validate(definition.value_type, value, definition.config)
        errors[key] = type_errors if type_errors.any?
      end

      Result.new(valid: errors.empty?, errors: errors)
    end
  end
end
