# frozen_string_literal: true

module FileImports
  class ProcessJob < ApplicationJob
    queue_as :default

    def perform(file_import_id)
      import = FileImport.find(file_import_id)
      return if import.completed?

      # Phase 1: Convert file to markdown
      import.update!(status: "converting", started_at: Time.current)
      import.broadcast_progress!

      markdown = import.source_file.open do |tempfile|
        ConvertService.call(
          file_path: tempfile.path,
          content_type: import.source_file.content_type
        )
      end

      # Phase 1.5: Sanitize markdown
      report = SanitizeService.call(markdown: markdown, filename: import.original_filename)

      unless report.usable
        raise ImportError, "[quality] #{report.warnings.first}"
      end

      markdown = report.markdown

      # Phase 1.75: AI enrichment (formatting + wikilinks to existing notes)
      if ai_enabled_for_import?
        import.update!(status: "enriching")
        import.broadcast_progress!

        markdown = ImportEnrichService.call(
          markdown: markdown,
          filename: import.original_filename
        )
      end

      # Phase 2: AI-assisted analysis (best-effort)
      ai_suggestions = nil
      if ai_enabled_for_import?
        import.update!(status: "analyzing")
        import.broadcast_progress!

        ai_suggestions = AiAnalyzeService.call(
          markdown: markdown,
          filename: import.original_filename
        )
      end

      # Phase 3: Generate split suggestions (AI or heading-based fallback)
      suggestions = if ai_suggestions.present?
        ai_suggestions
      else
        SplitSuggestionService.call(
          markdown: markdown,
          filename: import.original_filename,
          split_level: import.split_level.presence || 0
        )
      end

      import.update!(
        converted_markdown: markdown,
        suggested_splits: suggestions.map(&:to_h),
        status: "preview"
      )
      import.broadcast_progress!
    rescue ConvertService::ConversionError => e
      fail_import!(import, "[converting] #{e.message}")
    rescue ImportError => e
      fail_import!(import, e.message)
    rescue => e
      fail_import!(import, "[unexpected] #{e.message}")
    end

    private

    def ai_enabled_for_import?
      Ai::ProviderRegistry.enabled? &&
        Ai::ProviderRegistry.available_provider_names.any? { |n| n.start_with?("ollama") }
    end

    def fail_import!(import, message)
      import&.update!(
        status: "failed",
        error_message: message.truncate(2000),
        completed_at: Time.current
      )
      import&.broadcast_progress!
    end

    ImportError = Class.new(StandardError)
  end
end
