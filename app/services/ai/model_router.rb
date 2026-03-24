module Ai
  class ModelRouter
    class << self
      def route(provider_name:, configured_model:, capability:, text:, language: nil, target_language: nil, available_models: [])
        return selection(configured_model, strategy: "configured_default", reason: "provider_non_ollama") unless provider_name == "ollama"

        route_ollama(
          configured_model: configured_model,
          capability: capability,
          text: text,
          language: language,
          target_language: target_language,
          available_models: available_models
        )
      end

      private

      def route_ollama(configured_model:, capability:, text:, language:, target_language:, available_models:)
        text_length = text.to_s.length

        case capability.to_s
        when "grammar_review"
          if text_length <= threshold("OLLAMA_ROUTE_GRAMMAR_SHORT_MAX_CHARS", 800)
            selection(select_model("OLLAMA_ROUTE_GRAMMAR_SHORT_MODEL", ["qwen2.5:0.5b", "qwen2:1.5b", "qwen2.5:1.5b"], configured_model:, available_models:), reason: "grammar_short")
          else
            selection(select_model("OLLAMA_ROUTE_GRAMMAR_LONG_MODEL", ["qwen2.5:1.5b", "qwen2.5:3b", "llama3.2:3b"], configured_model:, available_models:), reason: "grammar_long")
          end
        when "rewrite"
          if text_length <= threshold("OLLAMA_ROUTE_REWRITE_SHORT_MAX_CHARS", 900)
            selection(select_model("OLLAMA_ROUTE_REWRITE_SHORT_MODEL", ["qwen2.5:1.5b", "qwen2:1.5b", "llama3.2:1b"], configured_model:, available_models:), reason: "rewrite_short")
          else
            selection(select_model("OLLAMA_ROUTE_REWRITE_LONG_MODEL", ["llama3.2:3b", "qwen2.5:3b", "qwen2.5:1.5b"], configured_model:, available_models:), reason: "rewrite_long")
          end
        when "seed_note"
          if text_length <= threshold("OLLAMA_ROUTE_SEED_NOTE_SHORT_MAX_CHARS", 1800)
            selection(select_model("OLLAMA_ROUTE_SEED_NOTE_SHORT_MODEL", ["qwen2.5:1.5b", "qwen2:1.5b", "llama3.2:1b"], configured_model:, available_models:), reason: "seed_note_short")
          else
            selection(select_model("OLLAMA_ROUTE_SEED_NOTE_LONG_MODEL", ["qwen2.5:3b", "llama3.2:3b", "qwen2.5:1.5b"], configured_model:, available_models:), reason: "seed_note_long")
          end
        when "translate"
          route_translation(text_length:, configured_model:, language:, target_language:, available_models:)
        else
          selection(configured_model, strategy: "configured_default", reason: "capability_fallback")
        end
      end

      def route_translation(text_length:, configured_model:, language:, target_language:, available_models:)
        source = language_family(language)
        target = language_family(target_language)

        if source == "pt" && target == "en"
          if text_length <= threshold("OLLAMA_ROUTE_TRANSLATE_PT_EN_SHORT_MAX_CHARS", 1200)
            selection(select_model("OLLAMA_ROUTE_TRANSLATE_PT_EN_SHORT_MODEL", ["qwen2:1.5b", "qwen2.5:1.5b", "llama3.2:1b"], configured_model:, available_models:), reason: "translate_pt_en_short")
          else
            selection(select_model("OLLAMA_ROUTE_TRANSLATE_PT_EN_LONG_MODEL", ["qwen2.5:3b", "qwen2.5:1.5b", "llama3.2:3b"], configured_model:, available_models:), reason: "translate_pt_en_long")
          end
        elsif source == "en" && target == "pt"
          if text_length <= threshold("OLLAMA_ROUTE_TRANSLATE_EN_PT_SHORT_MAX_CHARS", 1200)
            selection(select_model("OLLAMA_ROUTE_TRANSLATE_EN_PT_SHORT_MODEL", ["qwen2:1.5b", "qwen2.5:1.5b", "llama3.2:1b"], configured_model:, available_models:), reason: "translate_en_pt_short")
          else
            selection(select_model("OLLAMA_ROUTE_TRANSLATE_EN_PT_LONG_MODEL", ["qwen2.5:3b", "qwen2.5:1.5b", "llama3.2:3b"], configured_model:, available_models:), reason: "translate_en_pt_long")
          end
        elsif target == "en"
          selection(select_model("OLLAMA_ROUTE_TRANSLATE_TO_EN_MODEL", ["qwen2:1.5b", "qwen2.5:1.5b", "llama3.2:1b"], configured_model:, available_models:), reason: "translate_to_en")
        else
          selection(select_model("OLLAMA_ROUTE_TRANSLATE_GENERAL_MODEL", ["qwen2.5:3b", "qwen2.5:1.5b", "llama3.2:3b"], configured_model:, available_models:), reason: "translate_general")
        end
      end

      def language_family(value)
        value.to_s.downcase.split(/[-_]/).first.presence
      end

      def selection(model, strategy: "automatic", reason:)
        {
          model: model,
          selection_strategy: strategy,
          selection_reason: reason
        }
      end

      def threshold(key, default)
        value = ENV[key].to_i
        value.positive? ? value : default
      end

      def select_model(key, defaults, configured_model:, available_models:)
        preferences = preferred_models(key, defaults, configured_model:)
        normalized_available = Array(available_models).compact_blank
        return preferences.first if normalized_available.empty?

        preferences.find { |model| normalized_available.include?(model) } ||
          configured_model.presence&.then { |model| normalized_available.include?(model) ? model : nil } ||
          normalized_available.first
      end

      def preferred_models(key, defaults, configured_model:)
        configured_preferences = ENV[key].to_s.split(",").map(&:strip).reject(&:blank?)
        (configured_preferences + Array(defaults) + [configured_model]).compact_blank.uniq
      end
    end
  end
end
