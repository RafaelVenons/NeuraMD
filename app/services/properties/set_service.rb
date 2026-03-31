module Properties
  class SetService
    include ::DomainEvents

    UnknownKeyError = Class.new(StandardError)
    ValidationError = Class.new(StandardError) do
      attr_reader :details
      def initialize(details)
        @details = details
        super("Property validation failed: #{details.map { |k, e| "#{k}: #{e.join(", ")}" }.join("; ")}")
      end
    end

    def self.call(note:, changes:, author: nil)
      new(note:, changes:, author:).call
    end

    def initialize(note:, changes:, author:)
      @note = note
      @changes = changes
      @author = author
    end

    def call
      registry = PropertyDefinition.registry
      current = @note.head_revision&.properties_data&.dup || {}
      errors = {}
      casted_changes = {}

      @changes.each do |key, value|
        definition = registry[key]
        raise UnknownKeyError, "Unknown property key: #{key}" unless definition

        if value.nil?
          casted_changes[key] = nil
          next
        end

        casted = TypeRegistry.cast(definition.value_type, value, definition.config)
        type_errors = TypeRegistry.validate(definition.value_type, casted, definition.config)

        if type_errors.any?
          errors[key] = type_errors
        else
          casted_changes[key] = casted
        end
      end

      raise ValidationError, errors if errors.any?

      new_properties = current.dup
      casted_changes.each do |key, value|
        if value.nil?
          new_properties.delete(key)
        else
          new_properties[key] = value
        end
      end

      content = @note.head_revision&.content_markdown || ""

      result = Notes::CheckpointService.call(
        note: @note,
        content: content,
        author: @author,
        properties_data: new_properties
      )

      casted_changes.each do |key, value|
        action = value.nil? ? "removed" : (current.key?(key) ? "updated" : "set")
        publish_event("property.changed",
          note_id: @note.id,
          property: key,
          action: action,
          value: value)
      end

      result.revision
    end
  end
end
