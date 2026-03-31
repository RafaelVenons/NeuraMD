module Properties
  module Types
    module NoteReference
      UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

      def self.cast(raw, _config = {})
        raw.to_s.strip
      end

      def self.normalize(value, _config = {})
        return value unless value.is_a?(String)
        value.strip.downcase
      end

      def self.validate(value, _config = {})
        errors = []
        unless value.is_a?(String) && value.match?(UUID_PATTERN)
          errors << "must be a valid UUID"
          return errors
        end

        errors << "references a non-existent note" unless Note.where(id: value, deleted_at: nil).exists?
        errors
      end
    end
  end
end
