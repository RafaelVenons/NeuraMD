require_relative "error"
require_relative "model_router"
require_relative "openai_compatible_provider"
require_relative "anthropic_provider"
require_relative "ollama_provider"

module Ai
  class ProviderRegistry
    PROVIDER_PRIORITY = %w[openai anthropic ollama azure_openai local].freeze
    FALSE_VALUES = %w[0 false off no].freeze
    TRUE_VALUES = %w[1 true on yes].freeze

    class << self
      def status
        selected = selected_provider_name
        selected_model = selected ? provider_config(selected)[:model] : nil
        {
          enabled: enabled?,
          provider: selected,
          model: selected_model,
          available_providers: available_provider_names,
          provider_options: provider_options(selected:, selected_model:)
        }
      end

      def enabled?
        feature_enabled? && available_provider_names.any?
      end

      def available_provider_names
        provider_names.select { |name| configured?(name) }
      end

      def build(provider_name = nil, model_name: nil, capability: nil, text: nil, language: nil, target_language: nil)
        config = resolve_selection(
          provider_name,
          model_name: model_name,
          capability: capability,
          text: text,
          language: language,
          target_language: target_language
        )

        case config[:name]
        when "openai", "azure_openai", "local"
          OpenaiCompatibleProvider.new(**config.slice(:name, :model, :base_url, :api_key))
        when "anthropic"
          AnthropicProvider.new(**config.slice(:name, :model, :base_url, :api_key))
        when "ollama"
          OllamaProvider.new(**config.slice(:name, :model, :base_url, :api_key))
        else
          raise ProviderUnavailableError, "Provider #{config[:name]} nao suportado."
        end
      end

      def resolve_selection(provider_name = nil, model_name: nil, capability: nil, text: nil, language: nil, target_language: nil)
        resolved_name = resolve_provider_name(provider_name)
        config = provider_config(resolved_name)
        selection =
          if model_name.to_s.presence
            {
              model: model_name.to_s,
              selection_strategy: "manual_override",
              selection_reason: "ui_override"
            }
          else
            ModelRouter.route(
              provider_name: resolved_name,
              configured_model: config[:model],
              capability: capability,
              text: text,
              language: language,
              target_language: target_language
            )
          end

        config.merge(selection)
      end

      private

      def provider_options(selected:, selected_model:)
        available_provider_names.map do |name|
          config = provider_config(name)

          {
            name: name,
            label: provider_label(name),
            default_model: config[:model],
            models: available_models_for(name),
            selected: name == selected,
            selected_model: name == selected ? selected_model : config[:model]
          }
        end
      end

      def resolve_provider_name(provider_name)
        candidate = provider_name.to_s.presence || selected_provider_name
        raise ProviderUnavailableError, "IA nao configurada." if candidate.blank?
        raise ProviderUnavailableError, "Provider #{candidate} nao disponivel." unless available_provider_names.include?(candidate)

        candidate
      end

      def selected_provider_name
        available = available_provider_names
        return nil if available.empty?

        forced = ENV["AI_PROVIDER"].to_s.presence
        return forced if forced && available.include?(forced)

        priority_names.find { |name| available.include?(name) } || available.first
      end

      def provider_names
        names = parse_list(ENV["AI_ENABLED_PROVIDERS"])
        return names if names.any?

        db_names = AiProvider.enabled.pluck(:name)
        return db_names if db_names.any?

        PROVIDER_PRIORITY
      end

      def priority_names
        names = parse_list(ENV["AI_PROVIDER_PRIORITY"])
        names.any? ? names : PROVIDER_PRIORITY
      end

      def feature_enabled?
        value = ENV["AI_ENABLED"].to_s.downcase
        return false if FALSE_VALUES.include?(value)
        return true if TRUE_VALUES.include?(value)

        true
      end

      def configured?(name)
        config = provider_config(name)

        case name
        when "openai", "anthropic", "azure_openai"
          config[:api_key].present? && config[:model].present? && config[:base_url].present?
        when "ollama", "local"
          explicitly_enabled?(name) && config[:model].present? && config[:base_url].present?
        else
          false
        end
      end

      def explicitly_enabled?(name)
        parse_list(ENV["AI_ENABLED_PROVIDERS"]).include?(name) ||
          ENV["AI_PROVIDER"].to_s == name ||
          AiProvider.enabled.exists?(name: name) ||
          env_value(name, :base_url).present? ||
          env_value(name, :model).present?
      end

      def provider_config(name, model_name: nil)
        record = AiProvider.find_by(name: name)
        record_config = record&.config || {}
        resolved_model = model_name.to_s.presence ||
          record&.default_model_text.presence ||
          record_config["model"].presence ||
          env_value(name, :model) ||
          default_model(name)

        {
          name: name,
          model: resolved_model,
          base_url: record&.base_url.presence || record_config["base_url"].presence || env_value(name, :base_url) || default_base_url(name),
          api_key: env_value(name, :api_key)
        }
      end

      def available_models_for(name)
        record = AiProvider.find_by(name: name)
        record_models = normalize_models(record&.config&.fetch("models", nil))
        live_models = name == "ollama" ? OllamaProvider.available_models(base_url: provider_config(name)[:base_url]) : []
        configured_model = provider_config(name)[:model]

        (live_models + record_models + [configured_model]).compact_blank.uniq
      end

      def env_value(name, field)
        env_key = case [name, field]
        when ["openai", :api_key] then "OPENAI_API_KEY"
        when ["openai", :model] then "OPENAI_MODEL"
        when ["openai", :base_url] then "OPENAI_BASE_URL"
        when ["anthropic", :api_key] then "ANTHROPIC_API_KEY"
        when ["anthropic", :model] then "ANTHROPIC_MODEL"
        when ["anthropic", :base_url] then "ANTHROPIC_BASE_URL"
        when ["ollama", :api_key] then "OLLAMA_API_KEY"
        when ["ollama", :model] then "OLLAMA_MODEL"
        when ["ollama", :base_url] then "OLLAMA_API_BASE"
        when ["azure_openai", :api_key] then "AZURE_OPENAI_API_KEY"
        when ["azure_openai", :model] then "AZURE_OPENAI_MODEL"
        when ["azure_openai", :base_url] then "AZURE_OPENAI_BASE_URL"
        when ["local", :api_key] then "LOCAL_AI_API_KEY"
        when ["local", :model] then "LOCAL_AI_MODEL"
        when ["local", :base_url] then "LOCAL_AI_BASE_URL"
        end

        env_key ? ENV[env_key].presence : nil
      end

      def default_model(name)
        {
          "openai" => "gpt-4o-mini",
          "anthropic" => "claude-3-5-sonnet-latest",
          "ollama" => "llama3.2",
          "azure_openai" => nil,
          "local" => nil
        }[name]
      end

      def default_base_url(name)
        {
          "openai" => "https://api.openai.com/v1",
          "anthropic" => "https://api.anthropic.com/v1",
          "ollama" => "http://AIrch:11434",
          "azure_openai" => nil,
          "local" => "http://127.0.0.1:1234/v1"
        }[name]
      end

      def parse_list(value)
        value.to_s.split(",").map(&:strip).reject(&:blank?)
      end

      def normalize_models(value)
        case value
        when Array
          value.map(&:to_s).map(&:strip).reject(&:blank?)
        when String
          parse_list(value)
        else
          []
        end
      end

      def provider_label(name)
        {
          "openai" => "OpenAI",
          "anthropic" => "Anthropic",
          "azure_openai" => "Azure OpenAI",
          "ollama" => "Ollama",
          "local" => "Local"
        }[name] || name.humanize
      end
    end
  end
end
