module Properties
  class TypeRegistry
    include ExtensionPoint
    contract :cast, :normalize, :validate

    register :text, Types::Text
    register :long_text, Types::LongText
    register :number, Types::Number
    register :boolean, Types::Boolean
    register :date, Types::Date
    register :datetime, Types::Datetime
    register :enum, Types::Enum
    register :multi_enum, Types::MultiEnum
    register :url, Types::Url
    register :note_reference, Types::NoteReference
    register :list, Types::List

    freeze_registry!

    def self.handler_for(type_name)
      lookup(type_name)
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
