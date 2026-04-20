module Api
  class FileImportsController < BaseController
    def index
      imports = ::FileImport.recent.limit(50)
      render json: {imports: imports.map { |i| serialize(i) }}
    end

    private

    def serialize(import)
      {
        id: import.id,
        original_filename: import.original_filename,
        status: import.status,
        base_tag: import.base_tag,
        import_tag: import.import_tag,
        notes_created: import.notes_created,
        error_message: import.error_message,
        created_at: import.created_at.iso8601,
        completed_at: import.completed_at&.iso8601
      }
    end
  end
end
