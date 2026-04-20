class ExtensionManifest
  EXTENSION_POINTS = {
    search_operators: {
      registry: "Search::Dsl::OperatorRegistry",
      contract: [:apply],
      optional: [:validate],
      sealed: false,
      description: "Operadores DSL para busca (tag:x, link:y, etc.)"
    },
    renderers: {
      registry: "JS: RendererRegistry",
      contract: %i[name type selector fallbackHTML],
      sealed: false,
      description: "Post-processors de preview markdown"
    },
    property_types: {
      registry: "Properties::TypeRegistry",
      contract: %i[cast normalize validate],
      sealed: true,
      description: "Tipos de valor para propriedades de nota"
    },
    domain_events: {
      registry: "DOMAIN_EVENT_CATALOG",
      contract: [],
      sealed: false,
      description: "Eventos de domínio pub/sub via ActiveSupport::Notifications"
    },
    display_types: {
      registry: "NoteView::DISPLAY_TYPES",
      contract: [],
      sealed: true,
      description: "Tipos de visualização de NoteView (table, card, list)"
    }
  }.freeze

  SEALED_BOUNDARIES = %w[
    authentication
    authorization_policies
    database_schema
    model_core_validations
    route_structure
  ].freeze

  def self.all
    EXTENSION_POINTS
  end

  def self.extensible
    EXTENSION_POINTS.reject { |_, v| v[:sealed] }
  end

  def self.sealed
    EXTENSION_POINTS.select { |_, v| v[:sealed] }
  end

  def self.find(name)
    EXTENSION_POINTS.fetch(name.to_sym) do
      raise KeyError, "Unknown extension point: #{name}"
    end
  end
end
