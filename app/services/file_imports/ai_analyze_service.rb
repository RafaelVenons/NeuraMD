# frozen_string_literal: true

module FileImports
  class AiAnalyzeService
    TIMEOUT_SECONDS = 120

    def self.call(markdown:, filename: nil, provider_name: nil)
      new(markdown, filename, provider_name).call
    end

    def initialize(markdown, filename, provider_name)
      @markdown = markdown.to_s
      @filename = filename
      @lines = @markdown.lines.map(&:chomp)
      @provider_name = provider_name
    end

    def call
      return nil if @lines.empty?

      provider = build_provider
      return nil unless provider

      result = provider.review(
        capability: "import_analyze",
        text: @markdown,
        language: "pt"
      )

      parse_suggestions(result.content)
    rescue Ai::TransientRequestError, Ai::RequestError, JSON::ParserError => e
      Rails.logger.warn("[AiAnalyzeService] AI analysis failed: #{e.message}")
      nil
    rescue => e
      Rails.logger.warn("[AiAnalyzeService] Unexpected error: #{e.class} #{e.message}")
      nil
    end

    private

    def build_provider
      name = resolve_provider_name
      return nil unless name

      config = Ai::ProviderRegistry.resolve_selection(
        name,
        capability: "import_analyze",
        text: @markdown
      )

      case config[:name]
      when /\Aollama/
        Ai::OllamaProvider.new(**config.slice(:name, :model, :base_url, :api_key))
      else
        nil
      end
    rescue Ai::ProviderUnavailableError => e
      Rails.logger.warn("[AiAnalyzeService] No provider available: #{e.message}")
      nil
    end

    def resolve_provider_name
      return @provider_name if @provider_name.present?

      available = Ai::ProviderRegistry.available_provider_names
      available.find { |n| n.start_with?("ollama") }
    end

    def parse_suggestions(content)
      return nil if content.blank?

      json_text = extract_json(content)
      return nil if json_text.blank?

      entries = JSON.parse(json_text)
      return nil unless entries.is_a?(Array) && entries.any?

      suggestions = entries.filter_map { |entry| build_suggestion(entry) }
      return nil if suggestions.empty?

      validate_and_fix!(suggestions)
      suggestions
    end

    def extract_json(text)
      # Try to find JSON array in the response (may be wrapped in markdown fences)
      if (match = text.match(/\[[\s\S]*\]/))
        match[0]
      end
    end

    def build_suggestion(entry)
      return nil unless entry.is_a?(Hash)

      title = entry["title"].to_s.strip
      start_line = entry["start_line"].to_i
      end_line = entry["end_line"].to_i

      return nil if title.blank?
      return nil if end_line < start_line

      SplitSuggestionService::Suggestion.new(
        title: title,
        start_line: start_line,
        end_line: end_line,
        line_count: end_line - start_line + 1,
        level: 1
      )
    end

    def validate_and_fix!(suggestions)
      max_line = @lines.size - 1

      # Clamp end_line to document bounds
      suggestions.each do |s|
        s.start_line = [s.start_line, 0].max
        s.end_line = [s.end_line, max_line].min
        s.line_count = s.end_line - s.start_line + 1
      end

      # Sort by start_line
      suggestions.sort_by!(&:start_line)

      # Ensure contiguous coverage: fix gaps between suggestions
      suggestions.each_with_index do |s, i|
        next if i.zero?
        prev = suggestions[i - 1]
        if s.start_line > prev.end_line + 1
          # Gap: extend previous to cover it
          prev.end_line = s.start_line - 1
          prev.line_count = prev.end_line - prev.start_line + 1
        elsif s.start_line <= prev.end_line
          # Overlap: adjust current start
          s.start_line = prev.end_line + 1
          s.line_count = s.end_line - s.start_line + 1
        end
      end

      # Ensure last suggestion covers to end of document
      if suggestions.last.end_line < max_line
        suggestions.last.end_line = max_line
        suggestions.last.line_count = suggestions.last.end_line - suggestions.last.start_line + 1
      end

      # Ensure first suggestion starts at 0
      if suggestions.first.start_line > 0
        suggestions.first.start_line = 0
        suggestions.first.line_count = suggestions.first.end_line - suggestions.first.start_line + 1
      end

      # Remove suggestions that became invalid after fixes
      suggestions.reject! { |s| s.line_count <= 0 }
    end
  end
end
