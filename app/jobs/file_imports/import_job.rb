# frozen_string_literal: true

module FileImports
  class ImportJob < ApplicationJob
    queue_as :default

    def perform(file_import_id)
      import = FileImport.find(file_import_id)
      return unless import.preview? || import.status == "importing"

      import.update!(status: "importing")
      import.broadcast_progress!

      markdown = import.converted_markdown
      raise ImportError, "Markdown nao encontrado" if markdown.blank?

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
        created_notes_data: result["notes"] || [],
        completed_at: Time.current
      )
      import.broadcast_progress!
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
