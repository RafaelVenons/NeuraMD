module Properties
  module TypeRegistry
    TYPES = {
      "text" => Properties::Types::Text,
      "long_text" => Properties::Types::LongText,
      "number" => Properties::Types::Number,
      "boolean" => Properties::Types::Boolean,
      "date" => Properties::Types::Date,
      "datetime" => Properties::Types::Datetime,
      "enum" => Properties::Types::Enum,
      "multi_enum" => Properties::Types::MultiEnum,
      "url" => Properties::Types::Url,
      "note_reference" => Properties::Types::NoteReference,
      "list" => Properties::Types::List
    }.freeze

    def self.handler_for(type_name)
      TYPES.fetch(type_name) { raise ArgumentError, "Unknown property type: #{type_name}" }
    end

    def self.cast(type_name, raw_value, config = {})
      handler_for(type_name).cast(raw_value, config)
    end

    def self.normalize(type_name, value, config = {})
      handler_for(type_name).normalize(value, config)
    end

    def self.validate(type_name, value, config = {})
      handler_for(type_name).validate(value, config)
    end
  end
end
