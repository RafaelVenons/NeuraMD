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
        ConvertService.call(file_path: tempfile.path)
      end

      import.update!(converted_markdown: markdown, status: "importing")
      import.broadcast_progress!

      # Phase 2: Import markdown as notes
      response = Mcp::Tools::ImportMarkdownTool.call(
        markdown: markdown,
        base_tag: import.base_tag,
        import_tag: import.import_tag,
        extra_tags: import.extra_tags,
        split_level: import.split_level
      )

      if response.respond_to?(:error?) && response.error?
        error_text = response.content.first[:text]
        raise ImportError, "[importing] #{error_text}"
      end

      result_data = response.content.first[:text]
      result = JSON.parse(result_data)

      import.update!(
        status: "completed",
        notes_created: result["created_count"],
        completed_at: Time.current
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
