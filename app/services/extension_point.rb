module ExtensionPoint
  class ContractViolation < StandardError; end
  class UnknownExtension < StandardError; end

  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def contract(*methods)
      @required_methods = methods.map(&:to_sym)
    end

    def required_methods
      @required_methods || []
    end

    def register(name, handler)
      validate_contract!(name, handler)
      registry[name.to_s] = handler
    end

    def lookup(name)
      registry.fetch(name.to_s) do
        raise UnknownExtension, "Unknown #{self.name} extension: #{name}. Available: #{names.join(", ")}"
      end
    end

    def lookup_safe(name, fallback: nil)
      registry.fetch(name.to_s, fallback)
    end

    def registered?(name)
      registry.key?(name.to_s)
    end

    def names
      registry.keys.freeze
    end

    def freeze_registry!
      @frozen = true
      registry.freeze
    end

    def frozen_registry?
      @frozen == true
    end

    def default_handler(handler = nil)
      if handler
        @default_handler = handler
      else
        @default_handler
      end
    end

    def invoke_safe(name, *args, **kwargs)
      handler = lookup_safe(name, fallback: default_handler)
      return nil unless handler

      ActiveSupport::Notifications.instrument("extension.invoke", {
        extension_point: self.name,
        handler_name: name.to_s
      }) do
        handler.apply(*args, **kwargs)
      end
    rescue => e
      ActiveSupport::Notifications.instrument("extension.error", {
        extension_point: self.name,
        handler_name: name.to_s,
        error_class: e.class.name,
        error_message: e.message
      })
      Rails.logger.error("[ExtensionPoint] #{self.name}##{name} failed: #{e.message}")
      default_handler&.apply(*args, **kwargs)
    end

    private

    def registry
      @registry ||= {}
    end

    def validate_contract!(name, handler)
      raise "Registry is frozen — cannot register #{name}" if frozen_registry?
      missing = required_methods.reject { |m| handler.respond_to?(m) }
      return if missing.empty?
      raise ContractViolation,
        "#{handler} does not implement required methods for #{self.name}: #{missing.join(", ")}"
    end
  end
end
