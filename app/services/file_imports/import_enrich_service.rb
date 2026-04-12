# frozen_string_literal: true

module FileImports
  # Calls an Ollama model to fix formatting and inject wikilinks to existing notes
  # in a single pass. Returns enriched markdown on success, original markdown on
  # any failure (catalog empty, provider missing, content drift, exception).
  class ImportEnrichService
    Catalog = Struct.new(:title, :slug, :tags, keyword_init: true)

    CATALOG_LIMIT = 80
    KEYWORD_LIMIT = 30
    CONTENT_DRIFT_THRESHOLD = 0.85
    STOPWORDS = %w[
      sobre quando onde porque essa esses essas isso aquilo desse desta deste
      pelos pelas para esses estes estas todos todas mesmo mesma muito muita
      pode podem podia poderia entao ainda apenas alguns algumas dentro entre
    ].freeze

    def self.call(markdown:, filename: nil, provider_name: nil)
      new(markdown: markdown, filename: filename, provider_name: provider_name).call
    end

    def initialize(markdown:, filename: nil, provider_name: nil)
      @markdown = markdown.to_s
      @filename = filename
      @provider_name = provider_name
    end

    def call
      return @markdown if @markdown.blank?

      catalog = build_catalog
      return @markdown if catalog.empty?

      provider = build_provider
      return @markdown unless provider

      enriched = call_provider(provider, catalog)
      return @markdown if enriched.blank?

      enriched = resolve_slugs(enriched)
      validate_content_drift(@markdown, enriched)
    rescue Ai::TransientRequestError, Ai::RequestError => e
      Rails.logger.warn("[ImportEnrichService] AI failure: #{e.message}")
      @markdown
    rescue => e
      Rails.logger.warn("[ImportEnrichService] Unexpected: #{e.class} #{e.message}")
      @markdown
    end

    private

    def build_catalog
      keywords = extract_keywords(@markdown)
      return [] if keywords.empty?

      patterns = keywords.map { |k| "%#{Note.sanitize_sql_like(k)}%" }
      notes = Note.active
                  .where("title ILIKE ANY(ARRAY[?]::text[])", patterns)
                  .limit(CATALOG_LIMIT)
                  .includes(:tags)

      notes.map do |n|
        Catalog.new(title: n.title, slug: n.slug, tags: n.tags.pluck(:name).join(", "))
      end
    end

    def extract_keywords(markdown)
      headings = markdown.scan(/^#+\s+(.+)$/).flatten.map(&:strip)
      words = markdown.downcase.scan(/[a-záéíóúàãõâêôç]{5,}/i)
      freq = words.tally.reject { |w, _| STOPWORDS.include?(w) }
                  .sort_by { |_, c| -c }.first(20).map(&:first)
      (headings + freq).map(&:to_s).map(&:strip).reject(&:blank?).uniq.first(KEYWORD_LIMIT)
    end

    def build_provider
      name = resolve_provider_name
      return nil unless name

      config = Ai::ProviderRegistry.resolve_selection(
        name,
        capability: "import_enrich",
        text: @markdown
      )

      return nil unless config[:name].to_s.start_with?("ollama")

      Ai::OllamaProvider.new(**config.slice(:name, :model, :base_url, :api_key))
    rescue Ai::ProviderUnavailableError => e
      Rails.logger.warn("[ImportEnrichService] No provider: #{e.message}")
      nil
    end

    def resolve_provider_name
      return @provider_name if @provider_name.present?

      available = Ai::ProviderRegistry.available_provider_names
      preferred = ENV["IMPORT_AI_PROVIDER"].to_s.presence
      return preferred if preferred && available.include?(preferred)

      available.find { |n| n.start_with?("ollama") }
    end

    def call_provider(provider, catalog)
      catalog_text = catalog.map { |c|
        tags = c.tags.present? ? " [#{c.tags}]" : ""
        "- #{c.title} (slug: #{c.slug})#{tags}"
      }.join("\n")

      text = "## Catalogo de notas existentes:\n#{catalog_text}\n\n---\n\n## Documento a enriquecer:\n#{@markdown}"

      result = provider.review(capability: "import_enrich", text: text, language: "pt")
      result.content.to_s.strip
    end

    def resolve_slugs(markdown)
      markdown.gsub(/\[\[([^\]|]+)\|(\w):([a-z0-9-]+)\]\]/) do
        title = Regexp.last_match(1)
        role = Regexp.last_match(2)
        identifier = Regexp.last_match(3)

        # Already a UUID? leave as-is.
        next Regexp.last_match(0) if identifier.match?(Links::ExtractService::UUID_RE)

        uuid = Note.where(slug: identifier).pick(:id)
        uuid ? "[[#{title}|#{role}:#{uuid}]]" : Regexp.last_match(0)
      end
    end

    def validate_content_drift(original, enriched)
      clean_orig = strip_wikilinks(original).gsub(/\s+/, " ").strip
      clean_enrich = strip_wikilinks(enriched).gsub(/\s+/, " ").strip

      ratio = length_ratio(clean_orig, clean_enrich)
      if ratio < CONTENT_DRIFT_THRESHOLD
        Rails.logger.warn("[ImportEnrichService] Content drift #{ratio.round(2)} below threshold, rejecting")
        return original
      end

      enriched
    end

    def strip_wikilinks(text)
      text.gsub(/\[\[([^\]|]+)(?:\|[^\]]+)?\]\]/, '\1')
    end

    def length_ratio(a, b)
      return 1.0 if a.empty? && b.empty?
      shorter, longer = [a.length, b.length].minmax
      return 0.0 if longer.zero?
      shorter.to_f / longer
    end
  end
end
